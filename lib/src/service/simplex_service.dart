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
      final simplexDir = Directory('${docsDir.path}/simplex_data');
      await simplexDir.create(recursive: true);
      _appendLog('Data directory: ${simplexDir.path}');

      final initResult = await _native.migrateInitKey(
        path: simplexDir.path,
        key: '',
        keepKey: false,
        confirm: 'default',
        backgroundMode: 0,
      );
      _appendLog('migrateInitKey: $initResult');

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

  Future<void> sendTestCommand() async {
    if (!_isInitialized) {
      _appendLog('Core is not initialized. Press Init Core first.');
      return;
    }

    try {
      const cmd = '{"cmd":"api_version"}';
      _appendLog('> $cmd');
      final response = await _native.sendCommand(cmd);
      _appendLog('< $response');
    } catch (error, stackTrace) {
      _appendLog('sendCommand error: $error');
      _appendLog(stackTrace.toString());
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
