import 'dart:async';
import 'dart:convert';

import 'package:image/image.dart' as img;
import 'package:tanglex_chat/src/data/account_models.dart';
import 'package:tanglex_chat/src/data/chat_core.dart';
import 'package:tanglex_chat/src/data/connect_plan.dart';
import 'package:tanglex_chat/src/data/formatted_text.dart';
import 'package:tanglex_chat/src/providers/persistent_store.dart';

/// In-memory [ChatCore] for widget tests and golden snapshots.
class FakeChatCore implements ChatCore {
  FakeChatCore({
    required this.chats,
    Map<String, List<Map<String, dynamic>>>? messages,
    required this.now,
    List<Map<String, dynamic>>? users,
    int? activeUserId,
    Map<String, List<MessageSpan>>? markdown,
    this.address = 'simplex:/contact#/?v=2-7&smp=smp7.simplex.im%2Ftest#/Alex',
  }) : messages = messages ?? {},
       markdown = markdown ?? {},
       users = users ?? [_defaultUser()],
       _activeUserId = activeUserId;

  final List<ChatPreview> chats;
  final Map<String, List<Map<String, dynamic>>> messages;
  final DateTime now;
  final List<Map<String, dynamic>> users;

  /// What `chat_parse_markdown` would answer for a given text.
  final Map<String, List<MessageSpan>> markdown;
  final String? address;
  int? _activeUserId;

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  bool initialized = false;
  bool failSend = false;
  bool failConnect = false;
  final List<String> sentTexts = [];
  final List<int?> sentQuotedIds = [];
  final List<String> sentImagePaths = [];
  final List<String> sentFiles = [];
  final List<String> sentFileCaptions = [];
  final List<int> receivedFileIds = [];
  final List<String> sentImageCaptions = [];
  final List<({String chatRef, int itemId, String emoji, bool add})>
  reactionChanges = [];
  final List<({String chatRef, int itemId, String text})> edits = [];
  final List<({String chatRef, int itemId, bool forEveryone})> deletions = [];
  final List<({String toChatRef, String fromChatRef, int itemId})> forwards =
      [];
  final List<({int requestId, bool incognito})> acceptedRequests = [];
  final List<int> rejectedRequests = [];
  final List<String> readChats = [];
  final List<String> connectedLinks = [];
  final List<({String chatRef, bool muted})> muteChanges = [];

  static Map<String, dynamic> _defaultUser() => {
    'userId': 1,
    'localDisplayName': 'alex',
    'profile': {
      'displayName': 'Alex Morgan',
      'fullName': 'Alex Morgan Jr.',
      'shortDescr': 'Building TangleX',
    },
    'activeUser': true,
  };

  int? get _resolvedActiveUserId =>
      _activeUserId ?? (users.isEmpty ? null : users.first['userId'] as int);

  void _emit(String type) => _events.add({
    'result': {'type': type},
  });

  /// Emits a bare core event (the payload is not needed by list refreshes).
  void emitEvent(String type) => _emit(type);

  @override
  bool get isInitialized => initialized;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Stream<Map<String, dynamic>> get eventStream => _events.stream;

  @override
  Future<List<ChatPreview>> getChats({int limit = 50}) async => chats;

  @override
  Future<List<Map<String, dynamic>>> getChatMessages(
    String chatRef, {
    int limit = 50,
  }) async => List<Map<String, dynamic>>.from(messages[chatRef] ?? const []);

  @override
  Future<List<MessageSpan>?> parseMarkdown(String text) async => markdown[text];

  @override
  Future<bool> sendMessage(
    String chatRef,
    String text, {
    int? quotedItemId,
  }) async {    if (failSend) return false;
    sentTexts.add(text);
    sentQuotedIds.add(quotedItemId);
    final at = now.add(Duration(seconds: sentTexts.length));
    String? quoteText;
    if (quotedItemId != null) {
      for (final raw in messages[chatRef] ?? const []) {
        final meta = raw['meta'];
        if (meta is Map && meta['itemId'] == quotedItemId) {
          quoteText = meta['itemText'] as String?;
        }
      }
    }
    messages
        .putIfAbsent(chatRef, () => [])
        .add(
          textItem(
            text: text,
            time: at,
            fromMe: true,
            status: 'sndSent',
            quoteText: quoteText,
          ),
        );
    _emit('newChatItems');
    return true;
  }

  @override
  Future<bool> sendImages(
    String chatRef,
    List<OutgoingImage> images, {
    String text = '',
    int? quotedItemId,
  }) async {
    if (failSend || images.isEmpty) return false;
    sentImagePaths.addAll(images.map((image) => image.filePath));
    sentImageCaptions.add(text);
    sentQuotedIds.add(quotedItemId);
    final at = now.add(Duration(seconds: sentImagePaths.length));
    messages
        .putIfAbsent(chatRef, () => [])
        .add(
          imageItem(
            time: at,
            fileName: images.first.filePath.split('/').last,
            size: images.first.previewBytes.length,
            fromMe: true,
          ),
        );
    _emit('newChatItems');
    return true;
  }

  @override
  Future<bool> sendFile(
    String chatRef,
    String filePath, {
    String text = '',
    int? quotedItemId,
  }) async {
    if (failSend) return false;
    sentFiles.add(filePath);
    sentFileCaptions.add(text);
    sentQuotedIds.add(quotedItemId);
    final at = now.add(Duration(seconds: sentFiles.length));
    messages
        .putIfAbsent(chatRef, () => [])
        .add(
          documentItem(
            time: at,
            fileName: filePath.split('/').last,
            size: 1024,
            fromMe: true,
            fileStatus: 'sndComplete',
            filePath: filePath,
          ),
        );
    _emit('newChatItems');
    return true;
  }

  @override
  Future<bool> receiveFile(int fileId) async {
    if (failSend) return false;
    receivedFileIds.add(fileId);
    return true;
  }

  @override
  Future<bool> setReaction(
    String chatRef,
    int itemId,
    String emoji, {
    required bool add,
  }) async {
    reactionChanges.add((
      chatRef: chatRef,
      itemId: itemId,
      emoji: emoji,
      add: add,
    ));
    for (final raw in messages[chatRef] ?? const []) {
      final meta = raw['meta'];
      if (meta is! Map || meta['itemId'] != itemId) continue;
      final reactions = [
        for (final entry in (raw['reactions'] as List? ?? const []))
          if (entry is Map &&
              (entry['reaction'] as Map?)?['emoji'] != emoji)
            entry,
      ];
      if (add) {
        reactions.add({
          'reaction': {'type': 'emoji', 'emoji': emoji},
          'userReacted': true,
          'totalReacted': 1,
        });
      }
      raw['reactions'] = reactions;
    }
    _emit('chatItemReaction');
    return true;
  }

  @override
  Future<bool> editMessage(String chatRef, int itemId, String text) async {
    if (failSend) return false;
    edits.add((chatRef: chatRef, itemId: itemId, text: text));
    for (final raw in messages[chatRef] ?? const []) {
      final meta = raw['meta'];
      if (meta is! Map || meta['itemId'] != itemId) continue;
      meta['itemText'] = text;
      meta['itemEdited'] = true;
      final content = raw['content'];
      if (content is Map) {
        final msgContent = content['msgContent'];
        if (msgContent is Map) msgContent['text'] = text;
      }
    }
    _emit('chatItemUpdated');
    return true;
  }

  @override
  Future<bool> deleteMessage(
    String chatRef,
    int itemId, {
    required bool forEveryone,
  }) async {
    if (failSend) return false;
    deletions.add((chatRef: chatRef, itemId: itemId, forEveryone: forEveryone));
    messages[chatRef]?.removeWhere(
      (raw) => (raw['meta'] as Map?)?['itemId'] == itemId,
    );
    _emit('chatItemsDeleted');
    return true;
  }

  @override
  Future<bool> forwardMessages(
    String toChatRef,
    String fromChatRef,
    List<int> itemIds,
  ) async {
    if (failSend || itemIds.isEmpty) return false;
    for (final itemId in itemIds) {
      forwards.add((toChatRef: toChatRef, fromChatRef: fromChatRef, itemId: itemId));
      final source = messages[fromChatRef]?.firstWhere(
        (raw) => (raw['meta'] as Map?)?['itemId'] == itemId,
        orElse: () => const <String, dynamic>{},
      );
      final text = (source?['meta'] as Map?)?['itemText'];
      if (text is String && text.isNotEmpty) {
        final sourceName = chats
            .where((chat) => chat.chatRef == fromChatRef)
            .map((chat) => chat.displayName)
            .firstOrNull;
        messages
            .putIfAbsent(toChatRef, () => [])
            .add(
              textItem(
                text: text,
                time: now.add(Duration(seconds: forwards.length)),
                fromMe: true,
                forwarded: true,
                forwardedFrom: sourceName ?? '',
              ),
            );
      }
    }
    _emit('newChatItems');
    return true;
  }

  @override
  Future<bool> acceptContactRequest(
    int requestId, {
    bool incognito = false,
  }) async {
    acceptedRequests.add((requestId: requestId, incognito: incognito));
    _emit('contactConnected');
    return true;
  }

  @override
  Future<bool> rejectContactRequest(int requestId) async {
    rejectedRequests.add(requestId);
    _emit('contactRequestRejected');
    return true;
  }

  @override
  Future<void> markRead(String chatRef) async {
    readChats.add(chatRef);
  }

  @override
  Future<AccountsState> getAccounts() async {
    final activeId = _resolvedActiveUserId;
    return AccountsState(
      accounts: [
        for (final user in users)
          AccountProfile.fromUserJson(user, activeUserId: activeId),
      ],
      activeUserId: activeId,
    );
  }

  @override
  Future<bool> setActiveUser(int userId) async {
    if (!users.any((u) => u['userId'] == userId)) return false;
    _activeUserId = userId;
    _emit('activeUser');
    return true;
  }

  @override
  Future<AccountProfile?> createProfile({
    required String displayName,
    String fullName = '',
    String? shortDescr,
  }) async {
    final id = users.fold<int>(
      0,
      (max, user) => (user['userId'] as int) > max
          ? user['userId'] as int
          : max,
    ) + 1;
    final user = <String, dynamic>{
      'userId': id,
      'localDisplayName': displayName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ''),
      'profile': {
        'displayName': displayName,
        'fullName': fullName,
        'shortDescr': shortDescr ?? '',
      },
      'activeUser': true,
    };
    users.add(user);
    _activeUserId = id;
    _emit('activeUser');
    return AccountProfile.fromUserJson(user, activeUserId: id);
  }

  @override
  Future<bool> updateProfile(
    int userId, {
    required String displayName,
    String fullName = '',
    String? shortDescr,
    String? image,
  }) async {
    for (final user in users) {
      if (user['userId'] != userId) continue;
      user['profile'] = {
        'displayName': displayName,
        'fullName': fullName,
        'shortDescr': shortDescr ?? '',
        'image': ?image,
      };
      _emit('userProfileUpdated');
      return true;
    }
    return false;
  }

  @override
  Future<String?> getAddress() async => address;

  @override
  Future<ConnectOutcome> connectViaLink(String link) async {
    final target = link.trim();
    if (looksLikeShortLinkKey(target)) {
      return const ConnectOutcome.error(shortLinkKeyHint);
    }
    if (failConnect) {
      return const ConnectOutcome.error('This is not a valid SimpleX link.');
    }
    connectedLinks.add(target);
    return const ConnectOutcome.success();
  }

  @override
  Future<bool> setChatMuted(
    String chatRef, {
    required bool muted,
    required bool pinned,
  }) async {
    muteChanges.add((chatRef: chatRef, muted: muted));
    final index = chats.indexWhere((chat) => chat.chatRef == chatRef);
    if (index >= 0) {
      final old = chats[index];
      chats[index] = ChatPreview(
        chatRef: old.chatRef,
        chatType: old.chatType,
        displayName: old.displayName,
        lastMessage: old.lastMessage,
        timestamp: old.timestamp,
        unreadCount: old.unreadCount,
        chatId: old.chatId,
        contactStatus: old.contactStatus,
        contactUsed: old.contactUsed,
        avatarImage: old.avatarImage,
        lastFromMe: old.lastFromMe,
        connStatusType: old.connStatusType,
        embeddedContactRequestId: old.embeddedContactRequestId,
        muted: muted,
        pinned: pinned,
        fullName: old.fullName,
        shortDescr: old.shortDescr,
        description: old.description,
        memberCount: old.memberCount,
        quantumResistant: old.quantumResistant,
      );
    }
    _emit('chatItemUpdated');
    return true;
  }

  void dispose() => _events.close();
}

Map<String, dynamic> textItem({
  required String text,
  required DateTime time,
  bool fromMe = false,
  String status = 'sndSent',
  String? quoteText,
  String quoteDir = 'directRcv',
  List<Map<String, dynamic>> reactions = const [],
  List<Map<String, dynamic>>? formattedText,
  List<Map<String, dynamic>>? quoteFormattedText,
  bool edited = false,
  bool editable = false,
  bool deletable = false,
  bool forwarded = false,
  String forwardedFrom = '',
}) {
  return {
    'chatDir': {'type': fromMe ? 'directSnd' : 'directRcv'},
    'meta': {
      'itemId': time.millisecondsSinceEpoch,
      'itemTs': time.toUtc().toIso8601String(),
      'itemText': text,
      'itemStatus': {'type': fromMe ? status : 'rcvNew'},
      'itemEdited': edited,
      'editable': editable,
      'deletable': deletable,
      if (forwarded)
        'itemForwarded': {
          'type': forwardedFrom.isEmpty ? 'unknown' : 'contact',
          if (forwardedFrom.isNotEmpty) 'chatName': forwardedFrom,
        },
    },
    'content': {
      'type': fromMe ? 'sndMsgContent' : 'rcvMsgContent',
      'msgContent': {'type': 'text', 'text': text},
    },
    'reactions': reactions,
    'formattedText': ?formattedText,
    if (quoteText != null)
      'quotedItem': {
        'chatDir': {'type': quoteDir},
        'content': {'text': quoteText},
        'itemId': 1,
        'formattedText': ?quoteFormattedText,
      },
  };
}

String? _demoImageUri;

/// Deterministic 640x360 preview so photo bubbles exercise real bytes.
String demoImageUri() {
  final cached = _demoImageUri;
  if (cached != null) return cached;
  final picture = img.Image(width: 640, height: 360);
  img.fill(picture, color: img.ColorRgb8(20, 32, 44));
  for (var y = 0; y < picture.height; y++) {
    for (var x = 0; x < picture.width; x++) {
      final diagonal = (x + y) % 96;
      if (diagonal < 3) {
        img.drawPixel(picture, x, y, img.ColorRgb8(70, 120, 170));
      }
    }
  }
  final encoded = base64Encode(img.encodePng(picture));
  return _demoImageUri = 'data:image/png;base64,$encoded';
}

Map<String, dynamic> imageItem({
  required DateTime time,
  required String fileName,
  required int size,
  bool fromMe = false,
  int? fileId,
  String? fileStatus,
  int? progress,
  int? total,
  String? filePath,
}) {
  return {
    'chatDir': {'type': fromMe ? 'directSnd' : 'directRcv'},
    'meta': {
      'itemId': time.millisecondsSinceEpoch,
      'itemTs': time.toUtc().toIso8601String(),
      'itemText': '',
      'itemStatus': {'type': fromMe ? 'sndSent' : 'rcvNew'},
    },
    'content': {
      'type': fromMe ? 'sndMsgContent' : 'rcvMsgContent',
      'msgContent': {'type': 'image', 'text': '', 'image': demoImageUri()},
    },
    'file': {
      'fileName': fileName,
      'fileSize': size,
      'fileId': ?fileId,
      if (fileStatus != null)
        'fileStatus': {
          'type': fileStatus,
          (fromMe ? 'sndProgress' : 'rcvProgress'): ?progress,
          (fromMe ? 'sndTotal' : 'rcvTotal'): ?total,
        },
      if (filePath != null) 'fileSource': {'filePath': filePath},
    },
  };
}

Map<String, dynamic> documentItem({
  required DateTime time,
  required String fileName,
  required int size,
  bool fromMe = false,
  int? fileId,
  String? fileStatus,
  int? progress,
  int? total,
  String? filePath,
  String text = '',
}) {
  return {
    'chatDir': {'type': fromMe ? 'directSnd' : 'directRcv'},
    'meta': {
      'itemId': time.millisecondsSinceEpoch,
      'itemTs': time.toUtc().toIso8601String(),
      'itemText': text,
      'itemStatus': {'type': fromMe ? 'sndSent' : 'rcvNew'},
    },
    'content': {
      'type': fromMe ? 'sndMsgContent' : 'rcvMsgContent',
      'msgContent': {'type': 'file', 'text': text},
    },
    'file': {
      'fileName': fileName,
      'fileSize': size,
      'fileId': ?fileId,
      if (fileStatus != null)
        'fileStatus': {
          'type': fileStatus,
          (fromMe ? 'sndProgress' : 'rcvProgress'): ?progress,
          (fromMe ? 'sndTotal' : 'rcvTotal'): ?total,
        },
      if (filePath != null) 'fileSource': {'filePath': filePath},
    },
  };
}

int _micros(DateTime time) => time.microsecondsSinceEpoch;

/// The demo conversation that used to live in `demo_data.dart`, now expressed
/// as raw `/_get chat` items.
Map<String, List<Map<String, dynamic>>> demoConversations(DateTime day) {
  DateTime at(int hour, int minute) =>
      DateTime(day.year, day.month, day.day, hour, minute);
  return {
    '@1': [
      textItem(
        text: 'Привет! Скинул тебе доступ к тестовому серверу.',
        time: at(14, 20),
      ),
      textItem(
        text: 'Ключи в файле, порт 5223. Если не поднимется — пиши.',
        time: at(14, 21),
      ),
      textItem(
        text:
            'Проверил стык с ядром: каналы открываются, история подтягивается.',
        time: at(14, 22),
      ),
      textItem(text: 'Отлично, тогда вечером катим в ветку.', time: at(14, 22)),
      textItem(
        text: 'Принял. Сначала дизайн-система, потом фичи.',
        time: at(14, 26),
        fromMe: true,
        status: 'sndRcvd',
      ),
      textItem(
        text:
            'Согласен. И не забудь про темы — в TG можно поменять вообще всё.',
        time: at(14, 28),
        fromMe: true,
        status: 'sndRcvd',
        quoteText: 'Сначала дизайн-система, потом фичи.',
        quoteDir: 'directSnd',
      ),
      textItem(
        text: 'Записал: акцент, цвета бабблов, радиус, шрифт, обои.',
        time: at(14, 29),
        fromMe: true,
        status: 'sndSent',
      ),
      textItem(text: 'И pinned-чаты не забудь.', time: at(14, 30)),
      textItem(
        text: 'Вот как это выглядит с адаптивным каркасом 👇',
        time: at(14, 31),
      ),
      imageItem(
        time: at(14, 31),
        fileName: 'photo_2026-10-26_14-31-02.jpg',
        size: 412000,
      ),
      textItem(text: 'Sent you the room keys, see you at 8', time: at(14, 32)),
    ],
  };
}

/// Chat list rows mirroring the old demo data.
List<ChatPreview> demoChats(DateTime day) {
  DateTime at(int hour, int minute) =>
      DateTime(day.year, day.month, day.day, hour, minute);
  return [
    ChatPreview(
      chatRef: '@1',
      chatType: 'contact',
      displayName: 'Alice Bergström',
      lastMessage: 'Sent you the room keys, see you at 8',
      timestamp: _micros(at(14, 32)),
      unreadCount: 2,
      connStatusType: 'ready',
      fullName: 'Alice Bergström',
      shortDescr: 'Coffee, keys and long walks',
      quantumResistant: true,
    ),
    ChatPreview(
      chatRef: '#7',
      chatType: 'group',
      displayName: 'Meander Dev',
      lastMessage: 'pushed the FFI bridge, tests green',
      timestamp: _micros(at(13, 5)),
      unreadCount: 12,
      shortDescr: 'Build logs for TangleX',
      memberCount: 12,
    ),
    ChatPreview(
      chatRef: '#8',
      chatType: 'group',
      displayName: 'SimpleX News',
      lastMessage: 'Channels are now end-to-end encrypted',
      timestamp: _micros(at(12, 40)),
      muted: true,
      shortDescr: 'Release notes from the SimpleX team',
      memberCount: 1840,
    ),
    ChatPreview(
      chatRef: '#9',
      chatType: 'group',
      displayName: 'Server ops',
      lastMessage: 'Backup finished, 41 GB uploaded',
      timestamp: _micros(at(11, 18)),
      pinned: true,
      description: 'Only machines and their keepers here.',
      memberCount: 4,
    ),
    ChatPreview(
      chatRef: '@2',
      chatType: 'contact',
      displayName: 'Maria K.',
      lastMessage: 'Voice message · 0:24',
      timestamp: _micros(at(9, 2)),
      muted: true,
      connStatusType: 'ready',
      shortDescr: 'Designer',
    ),
    ChatPreview(
      chatRef: '#10',
      chatType: 'group',
      displayName: 'Saved messages',
      lastMessage: 'apt upgrade + reboot at 03:00',
      timestamp: _micros(DateTime(day.year, day.month, day.day - 1, 22, 40)),
      pinned: true,
    ),
    ChatPreview(
      chatRef: '@3',
      chatType: 'contact',
      displayName: 'Dan',
      lastMessage: 'OK',
      timestamp: _micros(DateTime(day.year, day.month, day.day - 2, 18, 15)),
      connStatusType: 'ready',
    ),
  ];
}
