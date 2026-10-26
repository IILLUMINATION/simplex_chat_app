import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/core_provider.dart';
import '../providers/persistent_store.dart';
import '../shell/models.dart';
import '../ui/chat/models/chat_message_models.dart';
import '../ui/chat/utils/chat_message_parser.dart';
import 'chat_core.dart';
import 'tanglex_chat_core.dart';

/// The production core; tests and previews override it with a fake.
final chatCoreProvider = Provider<ChatCore>(
  (ref) => TanglexChatCore(ref.watch(tanglexServiceProvider)),
);

/// Wall clock, injectable so goldens and tests can pin "today".
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Runs the (slow) core bootstrap once and exposes its result to the UI.
final coreReadyProvider = FutureProvider<void>((ref) async {
  final core = ref.watch(chatCoreProvider);
  await core.initialize();
});

const _chatListEvents = {
  'receivedContactRequest',
  'acceptingContactRequest',
  'contactRequestRejected',
  'chatStarted',
  'activeUser',
  'contactConnection',
  'contact',
  'contactSndReady',
  'contactConnecting',
  'chatItem',
  'chatItemNew',
  'newChatItems',
  'chatItemUpdated',
  'chatItemsDeleted',
  'chatItemsStatusesUpdated',
  'groupChatItemsDeleted',
  'chatDeleted',
  'chatCleared',
};

const _messageEvents = {
  'chatItem',
  'chatItemNew',
  'newChatItems',
  'chatItemUpdated',
  'chatItemsDeleted',
  'chatItemsStatusesUpdated',
  'groupChatItemsDeleted',
  'chatCleared',
};

/// Core events arrive wrapped as `{"result": {"type": ...}}`.
String? coreEventType(Map<String, dynamic> event) {
  final result = event['result'];
  if (result is Map) return result['type'] as String?;
  final type = event['type'];
  return type is String ? type : null;
}

final chatsProvider = AsyncNotifierProvider<ChatsNotifier, List<ChatSummary>>(
  ChatsNotifier.new,
);

class ChatsNotifier extends AsyncNotifier<List<ChatSummary>> {
  Timer? _debounce;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _disposed = false;

  @override
  Future<List<ChatSummary>> build() async {
    final core = ref.watch(chatCoreProvider);
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      _sub?.cancel();
    });
    await ref.watch(coreReadyProvider.future);
    _sub = core.eventStream.listen((event) {
      if (!_chatListEvents.contains(coreEventType(event))) return;
      _scheduleRefresh();
    });
    return _load(core);
  }

  Future<List<ChatSummary>> _load(ChatCore core) async {
    final previews = await core.getChats();
    final now = ref.read(clockProvider)();
    return previews.map((p) => chatSummaryFromPreview(p, now)).toList();
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), refresh);
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final core = ref.read(chatCoreProvider);
    try {
      final chats = await _load(core);
      if (_disposed) return;
      state = AsyncData(chats);
    } catch (error, stack) {
      if (_disposed) return;
      if (state.valueOrNull == null) state = AsyncError(error, stack);
    }
  }

  Future<bool> setMuted(String chatRef, {required bool muted}) async {
    final core = ref.read(chatCoreProvider);
    var pinned = false;
    for (final chat in state.valueOrNull ?? const <ChatSummary>[]) {
      if (chat.id == chatRef) pinned = chat.pinned;
    }
    final ok = await core.setChatMuted(chatRef, muted: muted, pinned: pinned);
    if (ok) await refresh();
    return ok;
  }
}

/// Bumped by the details panel to open in-conversation search.
final chatSearchRequestProvider = StateProvider.family<int, String>(
  (ref, chatRef) => 0,
);

ChatSummary chatSummaryFromPreview(ChatPreview preview, DateTime now) {
  final isGroup = preview.chatType == 'group';
  final ready = preview.isMessagingReady;
  final name = preview.displayName.isNotEmpty
      ? preview.displayName
      : (isGroup ? 'Group' : 'Contact');
  return ChatSummary(
    id: preview.chatRef,
    name: name,
    preview: preview.lastMessage,
    time: formatListTime(epochToDateTime(preview.timestamp), now),
    previewAuthor: preview.lastFromMe ? 'You' : null,
    subtitle: isGroup ? 'group' : (ready ? 'connected' : 'connecting…'),
    // SimpleX exposes no presence information, so no online dot is shown.
    online: false,
    unread: preview.unreadCount,
    muted: preview.muted,
    pinned: preview.pinned,
    isGroup: isGroup,
    canSend: ready,
    avatarBytes: preview.avatarImage,
  );
}

final messagesProvider =
    AsyncNotifierProvider.family<MessagesNotifier, List<MessageItem>, String>(
      MessagesNotifier.new,
    );

class MessagesNotifier extends FamilyAsyncNotifier<List<MessageItem>, String> {
  Timer? _debounce;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _disposed = false;

  @override
  Future<List<MessageItem>> build(String chatRef) async {
    final core = ref.watch(chatCoreProvider);
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      _sub?.cancel();
    });
    await ref.watch(coreReadyProvider.future);
    _sub = core.eventStream.listen((event) {
      if (!_messageEvents.contains(coreEventType(event))) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), _refresh);
    });
    return _fetch(core, chatRef);
  }

  Future<List<MessageItem>> _fetch(ChatCore core, String chatRef) async {
    final raw = await core.getChatMessages(chatRef);
    return buildTimeline(raw, now: ref.read(clockProvider)());
  }

  Future<void> _refresh() async {
    if (_disposed) return;
    final core = ref.read(chatCoreProvider);
    try {
      final timeline = await _fetch(core, arg);
      if (_disposed) return;
      state = AsyncData(timeline);
    } catch (_) {
      // Keep the current timeline; the next event retries.
    }
  }

  /// Appends the message immediately, then reconciles with the core.
  Future<bool> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final now = ref.read(clockProvider)();
    final optimistic = MessageItem(
      text: trimmed,
      time: DateFormat.Hm().format(now),
      timestamp: now,
      outgoing: true,
      status: MessageStatus.sending,
    );
    final current = state.valueOrNull ?? const <MessageItem>[];
    state = AsyncData([...current, optimistic]);

    final core = ref.read(chatCoreProvider);
    final ok = await core.sendMessage(arg, trimmed);
    if (_disposed) return ok;

    final updated = [...state.valueOrNull ?? const <MessageItem>[]];
    for (var i = updated.length - 1; i >= 0; i--) {
      final item = updated[i];
      if (item.outgoing &&
          item.text == trimmed &&
          item.status == MessageStatus.sending) {
        updated[i] = item.copyWith(
          status: ok ? MessageStatus.sent : MessageStatus.failed,
        );
        break;
      }
    }
    state = AsyncData(updated);
    return ok;
  }
}

// ===== Timeline mapping =====

/// Maps raw `/_get chat` items to bubble-ready rows, inserting day separators
/// and grouping consecutive messages.
List<MessageItem> buildTimeline(
  List<Map<String, dynamic>> rawItems, {
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final parsed = <(UiMessage, String?)>[];
  for (final raw in rawItems) {
    try {
      final item = Map<String, dynamic>.from(raw);
      final message = parseChatItem(item);
      if (message != null) parsed.add((message, _senderFrom(item)));
    } catch (_) {
      // A single malformed item must not blank out the conversation.
    }
  }
  parsed.sort((a, b) {
    final at = a.$1.time ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = b.$1.time ?? DateTime.fromMillisecondsSinceEpoch(0);
    return at.compareTo(bt);
  });

  final timeline = <MessageItem>[];
  DateTime? lastDay;
  for (final (message, sender) in parsed) {
    final time = message.time;
    if (time != null) {
      final day = DateTime(time.year, time.month, time.day);
      if (lastDay == null || day != lastDay) {
        timeline.add(
          MessageItem(
            text: formatDayLabel(day, reference),
            time: '',
            timestamp: time,
            isDateSeparator: true,
          ),
        );
        lastDay = day;
      }
    }
    timeline.add(_toItem(message, sender));
  }
  _applyGrouping(timeline);
  return timeline;
}

/// Group messages carry the author in `chatDir.groupMember`.
String? _senderFrom(Map<String, dynamic> raw) {
  final dir = raw['chatDir'];
  if (dir is! Map) return null;
  final member = dir['groupMember'];
  if (member is! Map) return null;
  final profile = member['memberProfile'];
  if (profile is Map) {
    final name = profile['displayName'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
  }
  final local = member['localDisplayName'];
  if (local is String && local.trim().isNotEmpty) return local.trim();
  return null;
}

MessageItem _toItem(UiMessage message, String? sender) {
  final quoted = message.quoted;
  final image = message.images.isEmpty ? null : message.images.first;
  return MessageItem(
    text: message.text,
    time: message.time != null
        ? DateFormat.Hm().format(message.time!)
        : message.timeStr,
    timestamp: message.time,
    outgoing: message.fromMe,
    sender: message.fromMe ? null : sender,
    status: message.fromMe
        ? _statusFromCore(message.status)
        : MessageStatus.none,
    isSystem: message.isSystem,
    mediaLabel: _mediaLabel(message),
    imageBytes: image?.bytes,
    imagePath: image?.filePath,
    reply: quoted == null
        ? null
        : MessageReply(
            author: quoted.senderName.isNotEmpty ? quoted.senderName : 'Reply',
            text: quoted.text,
          ),
  );
}

MessageStatus _statusFromCore(String raw) {
  return switch (raw) {
    'sndNew' => MessageStatus.sending,
    'sndSent' => MessageStatus.sent,
    'sndRcvd' => MessageStatus.delivered,
    'sndError' || 'sndErrorAuth' => MessageStatus.failed,
    _ => MessageStatus.none,
  };
}

String? _mediaLabel(UiMessage message) {
  if (message.images.isNotEmpty) {
    final image = message.images.first;
    final base = image.isSticker
        ? 'Sticker'
        : image.isVideo
        ? 'Video'
        : 'Photo';
    final size = image.fileSize;
    return size == null ? base : '$base · ${_formatBytes(size)}';
  }
  if (message.audio != null) return 'Voice message';
  if (message.fileName != null) {
    final size = message.fileSize;
    return size == null
        ? message.fileName
        : '${message.fileName} · ${_formatBytes(size)}';
  }
  return null;
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

void _applyGrouping(List<MessageItem> timeline) {
  for (var i = 0; i < timeline.length; i++) {
    final item = timeline[i];
    if (item.isDateSeparator || item.isSystem) continue;
    final previous = i > 0 ? timeline[i - 1] : null;
    final next = i + 1 < timeline.length ? timeline[i + 1] : null;
    timeline[i] = item.copyWith(
      firstInGroup: !_joinsGroup(previous, item),
      lastInGroup: !_joinsGroup(item, next),
    );
  }
}

bool _joinsGroup(MessageItem? first, MessageItem? second) {
  if (first == null || second == null) return false;
  if (first.isDateSeparator || second.isDateSeparator) return false;
  if (first.isSystem || second.isSystem) return false;
  if (first.outgoing != second.outgoing) return false;
  if (first.sender != second.sender) return false;
  final a = first.timestamp;
  final b = second.timestamp;
  if (a == null || b == null) return false;
  return b.difference(a).inMinutes.abs() < 5;
}

// ===== Time formatting =====

DateTime? epochToDateTime(int? value) {
  if (value == null || value <= 0) return null;
  if (value > 100000000000000) {
    return DateTime.fromMicrosecondsSinceEpoch(value);
  }
  if (value > 100000000000) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  return DateTime.fromMillisecondsSinceEpoch(value * 1000);
}

String formatListTime(DateTime? time, DateTime now) {
  if (time == null) return '';
  final day = DateTime(time.year, time.month, time.day);
  final today = DateTime(now.year, now.month, now.day);
  final delta = today.difference(day).inDays;
  if (delta == 0) return DateFormat.Hm().format(time);
  if (delta == 1) return 'Yesterday';
  if (delta > 1 && delta < 7) return DateFormat.E().format(time);
  return DateFormat('dd.MM.yy').format(time);
}

String formatDayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final delta = today.difference(day).inDays;
  if (delta == 0) return 'Today';
  if (delta == 1) return 'Yesterday';
  if (day.year == now.year) return DateFormat.MMMd().format(day);
  return DateFormat.yMMMd().format(day);
}
