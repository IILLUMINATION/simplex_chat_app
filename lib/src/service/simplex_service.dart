import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../ffi/simplex_native.dart';

class SimplexService {
  SimplexService({SimplexNative? native}) : _native = native ?? SimplexNative();

  final SimplexNative _native;

  final ValueNotifier<List<String>> logs = ValueNotifier<List<String>>(<String>[]);

  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _eventSubscription;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) {
      _appendLog('Core already initialized.');
      return;
    }

    try {
      _appendLog('Starting SimpleX core initialization...');

      final docsDir = await getApplicationDocumentsDirectory();
      final path =
          '${docsDir.path}/simplex_data_${DateTime.now().millisecondsSinceEpoch}';
      final simplexDir = Directory(path);
      simplexDir.createSync(recursive: true);
      _appendLog('Data directory: ${simplexDir.path}');

      final initResult = await _native.migrateInitKey(
        path: simplexDir.path,
      );
      _appendLog('migrateInitKey: $initResult');

      final normalized = initResult.toLowerCase();
      if (normalized.contains('error') || normalized.contains('invalid')) {
        throw Exception(initResult);
      }

      _receivePort = ReceivePort();
      _eventSubscription = _receivePort!.listen(_handleEvent);

      await _native.startEventLoop(_receivePort!.sendPort);
      _appendLog('Event loop started.');

      _isInitialized = true;
    } catch (error, stackTrace) {
      _appendLog('Initialization error: $error');
      _appendLog(stackTrace.toString());
      rethrow;
    }
  }

  Future<String?> sendCommand(String cmd) async {
    if (!_isInitialized) {
      _appendLog('Core is not initialized. Press Init Core first.');
      return null;
    }

    try {
      _appendLog('> $cmd');
      final response = await _native.sendCommand(cmd);
      _appendLog('< $response');
      return response;
    } catch (error, stackTrace) {
      _appendLog('sendCommand error: $error');
      _appendLog(stackTrace.toString());
      return null;
    }
  }

  void _handleEvent(dynamic event) {
    if (event is String) {
      _appendLog('[event] $event');
      return;
    }

    if (event is Map) {
      _appendLog('[event:error] ${event['error'] ?? event.toString()}');
      if (event['stackTrace'] != null) {
        _appendLog(event['stackTrace'].toString());
      }
      return;
    }

    _appendLog('[event:unknown] $event');
  }

  void _appendLog(String line) {
    print(line); // дублируем в stdout для отладки через терминал
    final updated = List<String>.from(logs.value)..add(line);
    logs.value = updated;
  }

  Future<void> dispose() async {
    _native.stopEventLoop();
    await _eventSubscription?.cancel();
    _receivePort?.close();
    logs.dispose();
  }
}
