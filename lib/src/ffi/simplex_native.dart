import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

import 'simplex_bindings.dart';

/// High-level wrapper over generated [SimplexBindings].
///
/// Responsibilities:
/// - loads native library (`libsimplex.so` on Android),
/// - initializes Haskell RTS once via `hs_init`,
/// - converts Dart strings to native UTF-8 and back,
/// - frees C strings returned by native functions,
/// - runs blocking receive loop in a dedicated isolate.
class SimplexNative {
  SimplexNative({ffi.DynamicLibrary? dynamicLibrary})
    : _providedLibrary = dynamicLibrary;

  final ffi.DynamicLibrary? _providedLibrary;
  late final ffi.DynamicLibrary _library = _providedLibrary ?? _openDynamicLibrary();
  late final SimplexBindings _bindings = SimplexBindings(_library);

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

  /// Initializes SimpleX core and captures `chat_ctrl` from `chat_migrate_init_key`.
  ///
  /// Returns JSON string provided by native function.
  Future<String> migrateInitKey({
    required String path,
    required String key,
    required bool keepKey,
    required String confirm,
    int backgroundMode = 0,
  }) async {
    await init();

    final pathPtr = path.toNativeUtf8();
    final keyPtr = key.toNativeUtf8();
    final confirmPtr = confirm.toNativeUtf8();
    final ctrlOut = calloc<chat_ctrl>();

    try {
      final resultPtr = _bindings.chat_migrate_init_key(
        pathPtr.cast<ffi.Char>(),
        keyPtr.cast<ffi.Char>(),
        keepKey ? 1 : 0,
        confirmPtr.cast<ffi.Char>(),
        backgroundMode,
        ctrlOut,
      );

      _chatController = ctrlOut.value;
      return _takeCStringAndFreeStatic(resultPtr);
    } finally {
      malloc.free(pathPtr);
      malloc.free(keyPtr);
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

  /// Sends JSON command into SimpleX core and returns JSON response.
  ///
  /// Uses [Future.microtask] so call site is async-friendly and does not block
  /// UI scheduling directly.
  Future<String> sendCommand(String jsonCmd, {int retryNum = 0}) {
    return init().then((_) => Future<String>.microtask(() {
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
    }));
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
      debugName: 'simplex_event_loop',
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

    throw UnsupportedError('SimplexNative is configured only for Android now.');
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

    final bindings = SimplexBindings(_openDynamicLibrary());
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
