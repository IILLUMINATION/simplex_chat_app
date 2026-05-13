import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

import 'tanglex_bindings.dart';

/// High-level wrapper over generated [TanglexBindings].
///
/// Responsibilities:
/// - loads native library (`libsimplex.so` on Android),
/// - initializes Haskell RTS once via `hs_init`,
/// - converts Dart strings to native UTF-8 and back,
/// - frees C strings returned by native functions,
/// - runs blocking receive loop in a dedicated isolate.
class TanglexNative {
  TanglexNative({ffi.DynamicLibrary? dynamicLibrary})
    : _providedLibrary = dynamicLibrary;

  final ffi.DynamicLibrary? _providedLibrary;
  late final ffi.DynamicLibrary _library =
      _providedLibrary ?? _openDynamicLibrary();
  late final TanglexBindings _bindings = TanglexBindings(_library);

  static bool _hsInitialized = false;

  ffi.Pointer<ffi.Void>? _chatController;
  Isolate? _eventLoopIsolate;

  /// Call once before using any API that depends on Haskell runtime.
  ///
  /// Per process we try to do this only once.
  Future<void> init() async {
    if (_hsInitialized) {
      return;
    }

    _bindings.hs_init(0, ffi.nullptr);
    _hsInitialized = true;
  }

  /// Attaches an existing native `chat_ctrl` pointer obtained earlier.
  void attachChatController(ffi.Pointer<ffi.Void> chatController) {
    _chatController = chatController;
  }

  /// Attaches chat controller by raw address (useful when restoring state).
  void attachChatControllerAddress(int address) {
    _chatController = ffi.Pointer<ffi.Void>.fromAddress(address);
  }

  /// Exposes raw controller address to pass across isolates.
  int? get chatControllerAddress => _chatController?.address;

  /// Initializes TangleX core and captures `chat_ctrl` from `chat_migrate_init_key`.
  ///
  /// Returns JSON string provided by native function.
  ///
  /// [confirm] must be one of: 'yesUp', 'yesUpDown', or 'error'.
  /// This is a migration confirmation, NOT a password confirmation.
  Future<String> migrateInitKey({
    required String path,
    String confirm = 'yesUp',
  }) async {
    await init();

    const strongPass = 'Tanglex_Strong_Password_12345!!!';
    final pathPtr = path.toNativeUtf8();
    final passPtr = strongPass.toNativeUtf8();
    final confirmPtr = confirm.toNativeUtf8();
    final ctrlOut = calloc<chat_ctrl>();

    try {
      print(
        'Calling Haskell: path=$path, pass=$strongPass, confirm=$confirm, keepKey=0',
      );
      final resultPtr = _bindings.chat_migrate_init_key(
        pathPtr.cast<ffi.Char>(),
        passPtr.cast<ffi.Char>(),
        0,
        confirmPtr.cast<ffi.Char>(),
        0,
        ctrlOut,
      );
      final result = _takeCStringAndFreeStatic(resultPtr);
      print('Haskell Response: $result');

      _chatController = ctrlOut.value;
      return result;
    } finally {
      malloc.free(pathPtr);
      malloc.free(passPtr);
      malloc.free(confirmPtr);
      calloc.free(ctrlOut);
    }
  }

  /// Converts Dart [value] into a native UTF-8 pointer.
  ///
  /// Caller owns pointer and must free it with [malloc.free].
  ffi.Pointer<Utf8> toNativeUtf8(String value) => value.toNativeUtf8();

  /// Converts native UTF-8 [value] into Dart [String].
  String fromNativeUtf8(ffi.Pointer<Utf8> value) => value.toDartString();

  /// Converts and frees C string returned by native functions.
  ///
  /// Native side is expected to return memory that can be freed with `malloc`.
  String takeCStringAndFree(ffi.Pointer<ffi.Char> ptr) {
    return _takeCStringAndFreeStatic(ptr);
  }

  /// Sends JSON command into TangleX core and returns JSON response.
  ///
  /// Uses [Future.microtask] so call site is async-friendly and does not block
  /// UI scheduling directly.
  Future<String> sendCommand(String jsonCmd, {int retryNum = 0}) {
    return init().then(
      (_) => Future<String>.microtask(() {
        final ctrl = _requireChatController();
        final cmdPtr = jsonCmd.toNativeUtf8();

        try {
          final resultPtr = _bindings.chat_send_cmd_retry(
            ctrl,
            cmdPtr.cast<ffi.Char>(),
            retryNum,
          );

          return _takeCStringAndFreeStatic(resultPtr);
        } finally {
          malloc.free(cmdPtr);
        }
      }),
    );
  }

  /// Starts blocking receive loop in a dedicated isolate.
  ///
  /// Each received JSON message is sent to [sendPort].
  Future<void> startEventLoop(SendPort sendPort, {int waitSeconds = 1}) async {
    await init();

    final ctrlAddress = _requireChatController().address;

    _eventLoopIsolate ??= await Isolate.spawn<Map<String, Object>>(
      _eventLoopEntryPoint,
      <String, Object>{
        'sendPort': sendPort,
        'chatCtrlAddress': ctrlAddress,
        'waitSeconds': waitSeconds,
      },
      debugName: 'tanglex_event_loop',
    );
  }

  /// Stops event loop isolate if it was started.
  void stopEventLoop() {
    _eventLoopIsolate?.kill(priority: Isolate.immediate);
    _eventLoopIsolate = null;
  }

  ffi.Pointer<ffi.Void> _requireChatController() {
    final ctrl = _chatController;
    if (ctrl == null || ctrl == ffi.nullptr) {
      throw StateError(
        'chat controller is not set. Call attachChatController(...) first.',
      );
    }

    return ctrl;
  }

  static ffi.DynamicLibrary _openDynamicLibrary() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libsimplex.so');
    }
    if (Platform.isLinux) {
      // На Linux библиотека libHSsimplex-chat-*.so лежит в lib/ рядом с бинарником
      // Flutter Linux bundle помещает ресурсы в data/flutter_assets/, но нативные .so
      // должны быть в lib/ относительно исполняемого файла.
      try {
        return ffi.DynamicLibrary.open('lib/libsimplex.so');
      } catch (e) {
        // Пробуем другие варианты
        final possiblePaths = [
          'libsimplex.so',
          'lib/x86_64-linux-gnu/libsimplex.so',
        ];
        for (final path in possiblePaths) {
          try {
            return ffi.DynamicLibrary.open(path);
          } catch (_) {}
        }
        throw UnsupportedError(
          'Не удалось найти libsimplex.so на Linux. '
          'Убедитесь, что файлы из simplex_extracted/opt/simplex/lib/app/resources/ '
          'скопированы в lib/ вашего Linux бандла.',
        );
      }
    }

    throw UnsupportedError(
      'TanglexNative поддерживает только Android и Linux.',
    );
  }

  static String _takeCStringAndFreeStatic(ffi.Pointer<ffi.Char> ptr) {
    if (ptr == ffi.nullptr) {
      return '';
    }

    final utf8Ptr = ptr.cast<Utf8>();
    final value = utf8Ptr.toDartString();
    malloc.free(utf8Ptr);
    return value;
  }

  @pragma('vm:entry-point')
  static void _eventLoopEntryPoint(Map<String, Object> args) {
    final sendPort = args['sendPort']! as SendPort;
    final chatCtrlAddress = args['chatCtrlAddress']! as int;
    final waitSeconds = args['waitSeconds']! as int;

    final bindings = TanglexBindings(_openDynamicLibrary());
    final chatCtrl = ffi.Pointer<ffi.Void>.fromAddress(chatCtrlAddress);

    while (true) {
      try {
        final msgPtr = bindings.chat_recv_msg_wait(chatCtrl, waitSeconds);
        final message = _takeCStringAndFreeStatic(msgPtr);

        if (message.isNotEmpty) {
          sendPort.send(message);
        }
      } catch (error, stackTrace) {
        sendPort.send(<String, String>{
          'type': 'error',
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        });
      }
    }
  }
}
