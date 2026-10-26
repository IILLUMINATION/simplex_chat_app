import 'dart:async';

import 'package:tanglex_chat/src/data/account_models.dart';
import 'package:tanglex_chat/src/data/chat_core.dart';
import 'package:tanglex_chat/src/data/connect_plan.dart';
import 'package:tanglex_chat/src/providers/persistent_store.dart';

/// In-memory [ChatCore] for widget tests and golden snapshots.
class FakeChatCore implements ChatCore {
  FakeChatCore({
    required this.chats,
    Map<String, List<Map<String, dynamic>>>? messages,
    required this.now,
    List<Map<String, dynamic>>? users,
    int? activeUserId,
    this.address = 'simplex:/contact#/?v=2-7&smp=smp7.simplex.im%2Ftest#/Alex',
  }) : messages = messages ?? {},
       users = users ?? [_defaultUser()],
       _activeUserId = activeUserId;

  final List<ChatPreview> chats;
  final Map<String, List<Map<String, dynamic>>> messages;
  final DateTime now;
  final List<Map<String, dynamic>> users;
  final String? address;
  int? _activeUserId;

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  bool initialized = false;
  bool failSend = false;
  bool failConnect = false;
  final List<String> sentTexts = [];
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
  Future<bool> sendMessage(
    String chatRef,
    String text, {
    int? quotedItemId,
  }) async {
    if (failSend) return false;
    sentTexts.add(text);
    final at = now.add(Duration(seconds: sentTexts.length));
    messages
        .putIfAbsent(chatRef, () => [])
        .add(textItem(text: text, time: at, fromMe: true, status: 'sndSent'));
    _emit('newChatItems');
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
  }) async {
    for (final user in users) {
      if (user['userId'] != userId) continue;
      user['profile'] = {
        'displayName': displayName,
        'fullName': fullName,
        'shortDescr': shortDescr ?? '',
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
  String? quoteSender,
}) {
  return {
    'chatDir': {'type': fromMe ? 'directSnd' : 'directRcv'},
    'meta': {
      'itemId': time.millisecondsSinceEpoch,
      'itemTs': time.toUtc().toIso8601String(),
      'itemText': text,
      'itemStatus': {'type': fromMe ? status : 'rcvNew'},
    },
    'content': {
      'type': fromMe ? 'sndMsgContent' : 'rcvMsgContent',
      'msgContent': {'type': 'text', 'text': text},
    },
    if (quoteText != null)
      'quotedItem': {
        'content': {'text': quoteText},
        'senderName': quoteSender ?? '',
        'itemId': 1,
      },
  };
}

Map<String, dynamic> imageItem({
  required DateTime time,
  required String fileName,
  required int size,
  bool fromMe = false,
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
      'msgContent': {'type': 'image', 'text': ''},
    },
    'file': {'fileName': fileName, 'fileSize': size},
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
        quoteSender: 'You',
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
    ),
    ChatPreview(
      chatRef: '#7',
      chatType: 'group',
      displayName: 'Meander Dev',
      lastMessage: 'pushed the FFI bridge, tests green',
      timestamp: _micros(at(13, 5)),
      unreadCount: 12,
    ),
    ChatPreview(
      chatRef: '#8',
      chatType: 'group',
      displayName: 'SimpleX News',
      lastMessage: 'Channels are now end-to-end encrypted',
      timestamp: _micros(at(12, 40)),
      muted: true,
    ),
    ChatPreview(
      chatRef: '#9',
      chatType: 'group',
      displayName: 'Server ops',
      lastMessage: 'Backup finished, 41 GB uploaded',
      timestamp: _micros(at(11, 18)),
      pinned: true,
    ),
    ChatPreview(
      chatRef: '@2',
      chatType: 'contact',
      displayName: 'Maria K.',
      lastMessage: 'Voice message · 0:24',
      timestamp: _micros(at(9, 2)),
      muted: true,
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
    ),
  ];
}
