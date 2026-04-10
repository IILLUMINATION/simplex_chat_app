import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../ffi/tanglex_native.dart';
import '../providers/persistent_store.dart';

class TanglexService {
  TanglexService({TanglexNative? native}) : _native = native ?? TanglexNative();

  final TanglexNative _native;

  final ValueNotifier<List<String>> logs = ValueNotifier<List<String>>(<String>[]);

  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _eventSubscription;
  bool _isInitialized = false;
  int? _activeUserId;
  bool _verboseLogs = false;
  bool _dumpedChatItem = true;

  bool get isInitialized => _isInitialized;

  // Stream of events for UI to listen to
  final StreamController<Map<String, dynamic>> _eventStream =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get eventStream => _eventStream.stream;

  Future<void> initialize() async {
    if (_isInitialized) {
      _appendLog('Core already initialized.');
      return;
    }

    try {
      _appendLog('Starting TangleX core initialization...');

      final docsDir = await getApplicationDocumentsDirectory();
      final basePath = '${docsDir.path}/tanglex_data';
      String pathToUse = basePath;
      Directory(pathToUse).createSync(recursive: true);
      _appendLog('Data directory: $pathToUse');

      String initResult = '';
      for (var attempt = 0; attempt < 3; attempt++) {
        initResult = await _native.migrateInitKey(
          path: pathToUse,
        );
        if (!_isDbLocked(initResult)) break;
        _appendLog('DB is locked, retrying init (${attempt + 1}/3)...');
        _native.stopEventLoop();
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }

      if (_isDbLocked(initResult)) {
        // Hot-restart can leave the previous native core holding the DB lock.
        // Fallback to a temporary directory so dev session can continue.
        final hotPath =
            '${docsDir.path}/tanglex_data_hot_${DateTime.now().millisecondsSinceEpoch}';
        _appendLog(
            'DB still locked. Falling back to temporary data dir: $hotPath');
        Directory(hotPath).createSync(recursive: true);
        pathToUse = hotPath;
        initResult = await _native.migrateInitKey(
          path: pathToUse,
        );
        _appendLog('migrateInitKey (hot): $initResult');
      }
      _appendLog('migrateInitKey: $initResult');

      final normalized = initResult.toLowerCase();
      if (normalized.contains('error') || normalized.contains('invalid')) {
        throw Exception(initResult);
      }

      _receivePort = ReceivePort();
      _eventSubscription = _receivePort!.listen(_handleEvent);

      await _native.startEventLoop(_receivePort!.sendPort);
      _appendLog('Event loop started.');

      await _setAppFilePaths();

      _isInitialized = true;
      await _ensureActiveUser();
      await _startChatIfPossible();
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
      _logVerbose('> $cmd');
      final response = await _native.sendCommand(cmd);
      _logVerbose('< $response');
      return response;
    } catch (error, stackTrace) {
      _appendLog('sendCommand error: $error');
      _appendLog(stackTrace.toString());
      return null;
    }
  }

  // ===== High-level API methods =====

  /// Get list of chats
  Future<List<ChatPreview>> getChats({int limit = 50}) async {
    final userId = await _getActiveUserId();
    if (userId == null) return [];
    final resp = await sendCommand('/_get chats $userId count=$limit');
    if (resp == null) return [];
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      if (json.containsKey('error')) {
        _appendLog('getChats error: ${json['error']}');
        return [];
      }
      final result = json['result'] as Map<String, dynamic>?;
      if (result == null) return [];
      final rType = result['type'] as String?;
      if (rType != 'chats' && rType != 'apiChats') return [];
      final chats = result['chats'] as List?;
      if (chats == null) return [];
      return chats
          .map((c) => ChatPreview.fromJson(Map<String, dynamic>.from(c)))
          .toList();
    } catch (e) {
      _appendLog('getChats parse error: $e');
      return [];
    }
  }

  /// Get messages in a specific chat
  Future<List<Map<String, dynamic>>> getChatMessages(String chatRef,
      {int limit = 50}) async {
    final resp = await sendCommand('/_get chat $chatRef count=$limit');
    if (resp == null) return [];
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      final result = json['result'] as Map<String, dynamic>?;
      if (result == null) return [];
      final rType = result['type'] as String?;
      final chatObj =
          (rType == 'apiChat' ? result['chat'] : result) as Map<String, dynamic>?;
      if (chatObj == null) return [];
      final items = chatObj['chatItems'] as List?;
      if (items == null) return [];
      if (!_dumpedChatItem && items.isNotEmpty) {
        _dumpedChatItem = true;
        try {
          final first = items.first;
          _appendLog('DEBUG first chatItem: ${_jsonCompact(first)}');
        } catch (_) {}
      }
      return items.map((i) => Map<String, dynamic>.from(i)).toList();
    } catch (e) {
      _appendLog('getChatMessages parse error: $e');
      return [];
    }
  }

  /// Get pending contact requests
  Future<List<ContactRequestPreview>> getContactRequests({int limit = 50}) async {
    final userId = await _getActiveUserId();
    if (userId == null) return [];
    final resp = await sendCommand('/_get chats $userId count=$limit');
    if (resp == null) return [];
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      final result = json['result'] as Map<String, dynamic>?;
      if (result == null) return [];
      final rType = result['type'] as String?;
      if (rType != 'chats' && rType != 'apiChats') return [];
      final chats = result['chats'] as List? ?? [];
      final requests = <ContactRequestPreview>[];
      for (final entry in chats) {
        if (entry is! Map) continue;
        final chatInfo = entry['chatInfo'] as Map<String, dynamic>?;
        if (chatInfo == null) continue;
        if (chatInfo['type'] != 'contactRequest') continue;
        final req = chatInfo['contactRequest'] as Map<String, dynamic>?;
        if (req == null) continue;
        requests.add(ContactRequestPreview.fromJson(req));
      }
      return requests;
    } catch (e) {
      _appendLog('getContactRequests parse error: $e');
      return [];
    }
  }

  /// Send a text message to a contact
  Future<bool> sendMessage(String chatRef, String text, {int? quotedItemId}) async {
    if (quotedItemId != null) {
      final payload = {
        'quotedItemId': quotedItemId,
        'msgContent': {
          'type': 'text',
          'text': text,
        },
      };
      final jsonStr = _jsonCompact([payload]);
      final cmd = '/_send $chatRef json $jsonStr';
      final resp = await sendCommand(cmd);
      if (resp == null) return false;
      try {
        final json = Map<String, dynamic>.from(_decodeJson(resp));
        return json['result'] != null;
      } catch (_) {
        return false;
      }
    }
    final cmd = '/_send $chatRef text ${_escapeText(text)}';
    final resp = await sendCommand(cmd);
    if (resp == null) return false;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      return json['result'] != null;
    } catch (e) {
      return false;
    }
  }

  Future<bool> sendImages(String chatRef, List<ImagePayload> images, {int? quotedItemId}) async {
    if (images.isEmpty) return false;
    final composed = <Map<String, dynamic>>[];
    for (int i = 0; i < images.length; i++) {
      final img = images[i];
      final payload = {
        'filePath': img.filePath,
        'msgContent': {
          'type': 'image',
          'text': '',
          'image': 'data:${img.previewMime};base64,${base64Encode(img.previewBytes)}',
        }
      };
      if (i == 0 && quotedItemId != null) {
        payload['quotedItemId'] = quotedItemId;
      }
      composed.add(payload);
    }
    final jsonStr = jsonEncode(composed);

    // Avoid largeMsg by splitting big payloads.
    if (jsonStr.length > 200000 && images.length > 1) {
      bool allOk = true;
      for (final img in images) {
        final part = jsonEncode([
          {
            'filePath': img.filePath,
            'msgContent': {
              'type': 'image',
              'text': '',
              'image':
                  'data:${img.previewMime};base64,${base64Encode(img.previewBytes)}',
            }
          }
        ]);
        final partCmd = '/_send $chatRef json $part';
        final partResp = await sendCommand(partCmd);
        if (partResp == null) {
          allOk = false;
          continue;
        }
        try {
          final json = Map<String, dynamic>.from(_decodeJson(partResp));
          if (json['result'] == null) allOk = false;
        } catch (_) {
          allOk = false;
        }
      }
      return allOk;
    }

    final cmd = '/_send $chatRef json $jsonStr';
    final resp = await sendCommand(cmd);
    if (resp == null) return false;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      return json['result'] != null;
    } catch (_) {
      return false;
    }
  }

  Future<SendResult> sendFile({
    required String chatRef,
    required String filePath,
    String text = '',
    int? quotedItemId,
  }) async {
    final payload = {
      'filePath': filePath,
      if (quotedItemId != null) 'quotedItemId': quotedItemId,
      'msgContent': {
        'type': 'file',
        'text': text,
      },
    };
    final jsonStr = _jsonCompact([payload]);
    final cmd = '/_send $chatRef json $jsonStr';
    final resp = await sendCommand(cmd);
    if (resp == null) {
      return const SendResult(ok: false, error: 'no response');
    }
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      if (json['result'] != null) return const SendResult(ok: true);
      if (json['error'] != null) {
        return SendResult(ok: false, error: _jsonCompact(json['error']));
      }
      return const SendResult(ok: false, error: 'unknown response');
    } catch (_) {
      return const SendResult(ok: false, error: 'parse error');
    }
  }

  Future<SendResult> sendVideo({
    required String chatRef,
    required String filePath,
    required Uint8List previewBytes,
    required int durationSec,
    String text = '',
    bool isCircle = false,
    int? quotedItemId,
  }) async {
    String pathToSend = filePath;
    if (isCircle) {
      try {
        final tmp = await getTemporaryDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final target = File('${tmp.path}/circle_$ts.mp4');
        final src = File(filePath);
        if (await src.exists()) {
          await src.copy(target.path);
          pathToSend = target.path;
        }
      } catch (_) {
        // If copy fails, fall back to original path.
        pathToSend = filePath;
      }
    }

    final payload = {
      'filePath': pathToSend,
      if (quotedItemId != null) 'quotedItemId': quotedItemId,
      'msgContent': {
        'type': 'video',
        'text': text,
        'image': 'data:image/jpeg;base64,${base64Encode(previewBytes)}',
        'duration': durationSec,
      },
    };
    final jsonStr = _jsonCompact([payload]);
    final cmd = '/_send $chatRef json $jsonStr';
    final resp = await sendCommand(cmd);
    if (resp == null) {
      return const SendResult(ok: false, error: 'no response');
    }
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      if (json['result'] != null) {
        return const SendResult(ok: true);
      }
      if (json['error'] != null) {
        return SendResult(ok: false, error: _jsonCompact(json['error']));
      }
      return const SendResult(ok: false, error: 'unknown response');
    } catch (_) {
      return const SendResult(ok: false, error: 'parse error');
    }
  }

  Future<SendResult> sendSticker({
    required String chatRef,
    required String filePath,
    required Uint8List previewBytes,
    required String previewMime,
    required String packId,
    required String stickerId,
  }) async {
    String pathToSend = filePath;
    try {
      final tmp = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final isWebmSrc = filePath.toLowerCase().endsWith('.webm');
      final ext = isWebmSrc ? 'webm' : 'webp';
      final target =
          File('${tmp.path}/st__${packId}__${stickerId}__$ts.$ext');
      final src = File(filePath);
      if (await src.exists()) {
        await src.copy(target.path);
        pathToSend = target.path;
      }
    } catch (_) {
      pathToSend = filePath;
    }

    final isWebm = filePath.toLowerCase().endsWith('.webm');
    final payload = {
      'filePath': pathToSend,
      'msgContent': {
        'type': isWebm ? 'video' : 'image',
        'text': '',
        'image': 'data:$previewMime;base64,${base64Encode(previewBytes)}',
        if (isWebm) 'duration': 0,
      },
    };
    final jsonStr = _jsonCompact([payload]);
    final cmd = '/_send $chatRef json $jsonStr';
    final resp = await sendCommand(cmd);
    if (resp == null) {
      return const SendResult(ok: false, error: 'no response');
    }
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      if (json['result'] != null) return const SendResult(ok: true);
      if (json['error'] != null) {
        return SendResult(ok: false, error: _jsonCompact(json['error']));
      }
      return const SendResult(ok: false, error: 'unknown response');
    } catch (_) {
      return const SendResult(ok: false, error: 'parse error');
    }
  }

  Future<bool> receiveFile(
    int fileId, {
    bool approvedRelays = true,
    bool? inline,
    bool encrypt = true,
    String? filePath,
  }) async {
    final buf = StringBuffer('/freceive $fileId');
    if (approvedRelays) {
      buf.write(' approved_relays=on');
    }
    buf.write(' encrypt=${encrypt ? 'on' : 'off'}');
    if (inline != null) {
      buf.write(' inline=${inline ? 'on' : 'off'}');
    }
    if (filePath != null && filePath.isNotEmpty) {
      buf.write(' $filePath');
    }
    final cmd = buf.toString();
    final resp = await sendCommand(cmd);
    if (resp == null) return false;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      if (json.containsKey('error')) return false;
      final result = json['result'] as Map<String, dynamic>?;
      if (result == null) return false;
      final type = result['type'] as String?;
      return type == 'rcvFileAccepted' || type == 'rcvFileAcceptedSndCancelled';
    } catch (_) {
      return false;
    }
  }

  /// Accept contact request
  Future<bool> acceptContactRequest(int contactRequestId) async {
    final resp = await sendCommand('/_accept $contactRequestId');
    if (resp == null) return false;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      if (json.containsKey('error')) return false;
      final result = json['result'] as Map<String, dynamic>?;
      return result != null && result['type'] == 'acceptingContactRequest';
    } catch (_) {
      return false;
    }
  }

  /// Reject contact request
  Future<bool> rejectContactRequest(int contactRequestId) async {
    final resp = await sendCommand('/_reject $contactRequestId');
    if (resp == null) return false;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      if (json.containsKey('error')) return false;
      final result = json['result'] as Map<String, dynamic>?;
      return result != null && result['type'] == 'contactRequestRejected';
    } catch (_) {
      return false;
    }
  }

  /// Create a user profile
  Future<Map<String, dynamic>?> createUserProfile({
    required String displayName,
    String fullName = '',
    String? shortDescr,
  }) async {
    final profile = {
      'profile': {
        'displayName': displayName,
        'fullName': fullName,
        'shortDescr': shortDescr,
        'image': null,
        'contactLink': null,
        'peerType': null,
        'preferences': null,
      },
      'pastTimestamp': false,
    };
    final resp = await sendCommand('/_create user ${_jsonCompact(profile)}');
    if (resp == null) return null;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      final result = json['result'] as Map<String, dynamic>?;
      if (result != null && result['type'] == 'activeUser') {
        final user = result['user'] as Map<String, dynamic>;
        _activeUserId = user['userId'] as int?;
        // Save profile locally
        await saveProfileData(ProfileData(
          displayName: displayName,
          fullName: fullName,
          shortDescr: shortDescr ?? '',
          userId: user['userId'] as int?,
          agentUserId: user['agentUserId'] as String?,
          userContactId: user['userContactId'] as int?,
          localDisplayName: user['localDisplayName'] as String?,
        ));
        return result;
      }
      return json;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Get current user info
  Future<Map<String, dynamic>?> getUser() async {
    final resp = await sendCommand('/user');
    if (resp == null) return null;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      final result = json['result'] as Map<String, dynamic>?;
      if (result == null || result['type'] != 'activeUser') return null;
      final user = result['user'] as Map<String, dynamic>?;
      if (user == null) return null;
      _activeUserId = user['userId'] as int?;
      return Map<String, dynamic>.from(user);
    } catch (e) {
      return null;
    }
  }

  /// Get all user profiles
  Future<List<Map<String, dynamic>>> getUsers() async {
    final resp = await sendCommand('/users');
    if (resp == null) return [];
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      final result = json['result'] as Map<String, dynamic>?;
      if (result == null || result['type'] != 'usersList') return [];
      final users = result['users'] as List? ?? [];
      return users
          .whereType<Map>()
          .map((u) => Map<String, dynamic>.from(u))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Set active user
  Future<bool> setActiveUser(int userId) async {
    final resp = await sendCommand('/_user $userId');
    if (resp == null) return false;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      if (json.containsKey('error')) return false;
      final result = json['result'] as Map<String, dynamic>?;
      if (result != null && result['type'] == 'activeUser') {
        _activeUserId = userId;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Create a connection link (long-term address)
  Future<String?> createConnectionLink() async {
    // Check if core is initialized
    if (!_isInitialized) {
      _appendLog('Error: Core not initialized');
      return null;
    }

    final resp = await sendCommand('/address');
    if (resp == null) return null;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));

      // Check for error
      if (json.containsKey('error')) {
        final errorObj = json['error'];
        final errorType = errorObj is Map ? errorObj['errorType'] : null;
        final errorCode = errorType is Map ? errorType['type'] : null;
        if (errorCode == 'duplicateContactLink') {
          return _getExistingAddress();
        }
        final message =
            errorType is Map ? (errorType['message'] ?? errorType['type']) : errorObj;
        _appendLog('createConnectionLink error: $message');
        return null;
      }

      final result = json['result'] as Map<String, dynamic>?;
      if (result == null) {
        _appendLog('createConnectionLink: empty result');
        return null;
      }

      // Try various field names for the link
      String? link;
      final connLinkContact = result['connLinkContact'];
      if (connLinkContact is Map) {
        link = connLinkContact['connFullLink'] as String? ??
            connLinkContact['connShortLink'] as String?;
      }
      link ??= result['connReqContactLink'] as String?;
      link ??= result['contactLink'] as String?;
      link ??= result['link'] as String?;

      if (link != null) {
        _appendLog('Connection link created successfully');
        return link;
      }

      _appendLog('createConnectionLink: no link field in result, type=${result['type']}');
      return null;
    } catch (e) {
      _appendLog('createConnectionLink parse error: $e');
      return null;
    }
  }

  Future<String?> _getExistingAddress() async {
    final user = await getUser();
    final userId = user?['userId'] as int?;
    if (userId == null) return null;
    final resp = await sendCommand('/_show_address $userId');
    if (resp == null) return null;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      if (json.containsKey('error')) return null;
      final result = json['result'] as Map<String, dynamic>?;
      if (result == null || result['type'] != 'userContactLink') return null;
      final contactLink = result['contactLink'] as Map<String, dynamic>?;
      if (contactLink == null) return null;
      final connLinkContact = contactLink['connLinkContact'];
      if (connLinkContact is Map) {
        return connLinkContact['connFullLink'] as String? ??
            connLinkContact['connShortLink'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Connect to a contact via their link
  Future<bool> connectViaLink(String link) async {
    // Check if core is initialized
    if (!_isInitialized) {
      _appendLog('Error: Core not initialized');
      return false;
    }

    final resp = await sendCommand('/connect $link');
    if (resp == null) return false;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));

      // Check for error
      if (json.containsKey('error')) {
        final errorObj = json['error'];
        final errorType = errorObj is Map ? errorObj['errorType'] : null;
        final message = errorType is Map ? errorType['message'] : errorObj;
        _appendLog('connectViaLink error: $message');
        return false;
      }

      final result = json['result'] as Map<String, dynamic>?;
      if (result == null) {
        _appendLog('connectViaLink: empty result');
        return false;
      }

      _appendLog('connectViaLink success, type=${result['type']}');
      return true;
    } catch (e) {
      _appendLog('connectViaLink parse error: $e');
      return false;
    }
  }

  /// Get pending connection requests
  Future<List<Map<String, dynamic>>> getPendingConnections() async {
    final userId = await _getActiveUserId();
    if (userId == null) return [];
    final resp = await sendCommand('/_get chats $userId pcc=on count=50');
    if (resp == null) return [];
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      final result = json['result'] as Map<String, dynamic>?;
      if (result == null) return [];
      final chats = result['chats'] as List? ?? [];
      return chats
          .where((c) => c is Map && c.containsKey('pccStatus'))
          .map((c) => Map<String, dynamic>.from(c))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Accept a pending contact connection
  Future<bool> acceptConnection(int connId) async {
    final resp = await sendCommand('/_accept incognito $connId');
    if (resp == null) return false;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      return json['result'] != null;
    } catch (e) {
      return false;
    }
  }

  /// Delete user profile
  Future<bool> deleteUser(int userId, {bool deleteSmpQueues = false}) async {
    final cmd =
        '/_delete user $userId del_smp=${deleteSmpQueues ? 'on' : 'off'}';
    _appendLog('deleteUser command: $cmd');
    final resp = await sendCommand(cmd);
    _appendLog('deleteUser response: $resp');
    if (resp == null) {
      _appendLog('deleteUser: null response');
      return false;
    }
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      _appendLog('deleteUser parsed: $json');
      if (json.containsKey('error')) {
        final errorObj = json['error'];
        final errorType = errorObj is Map ? errorObj['errorType'] : null;
        final errorCode = errorType is Map ? errorType['type'] : null;
        _appendLog('deleteUser error: type=$errorCode obj=$errorObj');
        if (errorCode == 'chatNotStarted') {
          _appendLog('deleteUser: retrying after _startChatIfPossible');
          await _startChatIfPossible();
          final retry = await sendCommand(cmd);
          if (retry == null) return false;
          final retryJson = Map<String, dynamic>.from(_decodeJson(retry));
          if (retryJson.containsKey('error')) {
            _appendLog('deleteUser retry error: ${retryJson['error']}');
            return false;
          }
          final retryResult = retryJson['result'] as Map<String, dynamic>?;
          _appendLog('deleteUser retry result: $retryResult');
          if (retryResult != null && retryResult['type'] == 'cmdOk') {
            if (_activeUserId == userId) _activeUserId = null;
            return true;
          }
          return false;
        }
        return false;
      }
      final result = json['result'] as Map<String, dynamic>?;
      _appendLog('deleteUser result: $result');
      if (result != null && result['type'] == 'cmdOk') {
        if (_activeUserId == userId) _activeUserId = null;
        return true;
      }
      _appendLog('deleteUser: result type "${result?['type']}" is not cmdOk');
      return false;
    } catch (e, st) {
      _appendLog('deleteUser exception: $e');
      _appendLog(st.toString());
      return false;
    }
  }

  void _handleEvent(dynamic event) {
    if (event is String) {
      _appendLog('[event] $event');
      try {
        final json = Map<String, dynamic>.from(_decodeJson(event));
        _eventStream.add(json);
      } catch (_) {}
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

  Future<void> _ensureActiveUser() async {
    final activeResp = await sendCommand('/user');
    if (activeResp == null) return;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(activeResp));
      final result = json['result'] as Map<String, dynamic>?;
      if (result != null && result['type'] == 'activeUser') {
        final user = result['user'] as Map<String, dynamic>?;
        _activeUserId = user?['userId'] as int?;
        return;
      }
      final errorObj = json['error'];
      final errorType = errorObj is Map ? errorObj['errorType'] : null;
      final errorCode = errorType is Map ? errorType['type'] : null;
      if (errorCode != 'noActiveUser') {
        return;
      }
    } catch (_) {
      // If parsing failed, do nothing.
      return;
    }

    final usersResp = await sendCommand('/users');
    if (usersResp == null) return;

    try {
      final json = Map<String, dynamic>.from(_decodeJson(usersResp));
      final result = json['result'] as Map<String, dynamic>?;
      if (result == null || result['type'] != 'usersList') return;
      final users = result['users'] as List? ?? [];

      final persisted = await loadProfileData();
      if (users.isEmpty) {
        if (persisted != null && persisted.displayName.isNotEmpty) {
          await createUserProfile(
            displayName: persisted.displayName,
            fullName: persisted.fullName,
            shortDescr: persisted.shortDescr.isEmpty ? null : persisted.shortDescr,
          );
        }
        return;
      }

      int? targetUserId = persisted?.userId;

      int? matchedUserId;
      for (final entry in users) {
        final userInfo = entry is Map ? entry['user'] : null;
        if (userInfo is Map) {
          final userId = userInfo['userId'] as int?;
          final isActive = userInfo['activeUser'] == true;
          if (isActive) {
            return;
          }
          if (targetUserId != null && userId == targetUserId) {
            matchedUserId = userId;
          }
        }
      }

      final fallbackUserInfo =
          users.first is Map ? (users.first as Map)['user'] : null;
      final fallbackUserId =
          fallbackUserInfo is Map ? fallbackUserInfo['userId'] as int? : null;

      final userIdToActivate = matchedUserId ?? fallbackUserId;
      if (userIdToActivate != null) {
        final resp = await sendCommand('/_user $userIdToActivate');
        if (resp != null) {
          _activeUserId = userIdToActivate;
        }
      }
    } catch (_) {
      return;
    }
  }

  Future<int?> _getActiveUserId() async {
    if (_activeUserId != null) return _activeUserId;
    final user = await getUser();
    return user?['userId'] as int?;
  }

  Future<void> _startChatIfPossible() async {
    final resp = await sendCommand('/_start');
    if (resp == null) return;
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      if (json.containsKey('error')) {
        // Ignore errors like noActiveUser; caller will handle when user exists.
        return;
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _setAppFilePaths() async {
    if (!Platform.isAndroid) return;

    final docsDir = await getApplicationDocumentsDirectory();
    final tempDir = await getTemporaryDirectory();

    final filesDir = '${docsDir.path}/files';
    final assetsDir = docsDir.path;

    Directory(filesDir).createSync(recursive: true);
    Directory(tempDir.path).createSync(recursive: true);
    Directory(assetsDir).createSync(recursive: true);

    final payload = <String, dynamic>{
      'appFilesFolder': filesDir,
      'appTempFolder': tempDir.path,
      'appAssetsFolder': assetsDir,
    };

    final cmd = '/set file paths ${_jsonCompact(payload)}';
    final resp = await sendCommand(cmd);
    if (resp == null) {
      _appendLog('apiSetAppFilePaths failed: no response');
      return;
    }
    try {
      final json = Map<String, dynamic>.from(_decodeJson(resp));
      if (json.containsKey('error')) {
        _appendLog('apiSetAppFilePaths error: ${json['error']}');
      }
    } catch (_) {
      // ignore parse errors; command is best-effort
    }
  }

  void _appendLog(String line) {
    print(line);
    final updated = List<String>.from(logs.value)..add(line);
    logs.value = updated;
  }

  void _logVerbose(String line) {
    if (_verboseLogs) {
      _appendLog(line);
    }
  }

  dynamic _decodeJson(String str) {
    return jsonDecode(str);
  }

  String _jsonCompact(dynamic obj) {
    return jsonEncode(obj);
  }

  String _escapeJson(String s) {
    return s.replaceAll('"', '\\"').replaceAll('\n', '\\n');
  }

  String _escapeText(String s) {
    return s.replaceAll('\n', '\\n');
  }

  bool _isDbLocked(String initResult) {
    try {
      final json = Map<String, dynamic>.from(_decodeJson(initResult));
      if (json['type'] != 'errorSQL') return false;
      final err = json['migrationSQLError']?.toString() ?? '';
      return err.contains('database is locked') || err.contains('ErrorBusy');
    } catch (_) {
      return initResult.contains('database is locked') ||
          initResult.contains('ErrorBusy');
    }
  }

  Future<void> dispose() async {
    _native.stopEventLoop();
    await _eventSubscription?.cancel();
    _receivePort?.close();
    _eventStream.close();
    logs.dispose();
  }
}

class SendResult {
  final bool ok;
  final String? error;

  const SendResult({required this.ok, this.error});
}

class ImagePayload {
  final String filePath;
  final Uint8List previewBytes;
  final String previewMime;
  const ImagePayload({
    required this.filePath,
    required this.previewBytes,
    required this.previewMime,
  });
}
