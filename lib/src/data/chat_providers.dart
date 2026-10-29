import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../notifications/notification_sink.dart';
import '../providers/core_provider.dart';
import '../providers/persistent_store.dart';
import '../shell/models.dart';
import '../ui/chat/models/chat_message_models.dart';
import '../ui/chat/utils/chat_message_parser.dart';
import 'chat_core.dart';
import 'formatted_text.dart';
import 'tanglex_chat_core.dart';

/// The production core; tests and previews override it with a fake.
final chatCoreProvider = Provider<ChatCore>(
  (ref) => TanglexChatCore(ref.watch(tanglexServiceProvider)),
);

/// Wall clock, injectable so goldens and tests can pin "today".
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Chat open in the conversation pane; Telegram doesn't notify about it.
final activeChatRefProvider = StateProvider<String?>((ref) => null);

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
  'contactConnected',
  'contactUpdated',
  'contactDeleted',
  'chatInfoUpdated',
  'contactSndReady',
  'contactConnecting',
  'chatItem',
  'chatItemNew',
  'newChatItems',
  'chatItemUpdated',
  'chatItemReaction',
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
  'chatItemReaction',
  'chatItemsDeleted',
  'chatItemsStatusesUpdated',
  'groupChatItemsDeleted',
  'chatCleared',
  // File transfers update `file.status` in the DB and emit these instead of
  // `chatItemUpdated`; without them the upload ring never moves. Mirrors the
  // official client, which patches the item from the event payload
  // (`SimpleXAPI.kt`, `CR.SndFileProgressXFTP`).
  'sndFileStart',
  'sndFileProgressXFTP',
  'sndFileComplete',
  'sndFileCompleteXFTP',
  'sndFileError',
  'sndFileWarning',
  'sndFileRcvCancelled',
  'rcvFileStart',
  'rcvFileProgressXFTP',
  'rcvFileComplete',
  'rcvFileError',
  'rcvFileSndCancelled',
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

  /// Unread counters from the previous refresh; a growth means new mail.
  final Map<String, int> _seenUnread = {};
  bool _unreadPrimed = false;

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
    final chats = await _load(core);
    // Whatever was unread before this session stays silent, like Telegram's
    // launch behaviour; only growth after the first load notifies.
    for (final chat in chats) {
      _seenUnread[chat.id] = chat.unread;
    }
    _unreadPrimed = true;
    return chats;
  }

  Future<List<ChatSummary>> _load(ChatCore core) async {
    final previews = await core.getChats();
    final now = ref.read(clockProvider)();
    return previews
        // v7 note folders ("local") and any unknown chatInfo type have no
        // renderable chat yet; showing them would produce a dead "@?" row.
        .where(
          (p) =>
              p.chatType == 'contact' ||
              p.chatType == 'group' ||
              p.chatType == 'contactRequest' ||
              p.chatType == 'contactConnection',
        )
        .map((p) => chatSummaryFromPreview(p, now))
        .toList();
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
      _notifyNewMail(chats);
    } catch (error, stack) {
      if (_disposed) return;
      if (state.valueOrNull == null) state = AsyncError(error, stack);
    }
  }

  /// `MainWidget`/`DialogsWidget` show a system notification for every chat
  /// whose unread counter grew, except muted ones and the open conversation.
  void _notifyNewMail(List<ChatSummary> chats) {
    final open = ref.read(activeChatRefProvider);
    final sink = ref.read(notificationSinkProvider);
    for (final chat in chats) {
      final previous = _seenUnread[chat.id];
      _seenUnread[chat.id] = chat.unread;
      if (!_unreadPrimed) continue;
      if (previous == null || chat.unread <= previous) continue;
      if (chat.muted || chat.id == open) continue;
      unawaited(
        sink
            .showMessage(
              chatRef: chat.id,
              title: chat.name,
              body: chat.preview.isEmpty ? 'New message' : chat.preview,
            )
            .catchError((Object error) {
              if (kDebugMode) {
                debugPrint('[Tanglex] notification failed: $error');
              }
            }),
      );
    }
    _unreadPrimed = true;
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
  final needsAccept = preview.needsAcceptFromDirectRow;
  final name = preview.displayName.isNotEmpty
      ? preview.displayName
      : (isGroup ? 'Group' : 'Contact');
  final members = preview.memberCount;
  final subtitle = isGroup
      ? (members == null
            ? 'group'
            : '$members ${members == 1 ? 'member' : 'members'}')
      : needsAccept
      ? 'contact request'
      : (ready ? 'connected' : 'connecting…');
  return ChatSummary(
    id: preview.chatRef,
    name: name,
    preview: preview.lastMessage,
    time: formatListTime(epochToDateTime(preview.timestamp), now),
    previewAuthor: preview.lastFromMe ? 'You' : null,
    subtitle: subtitle,
    // SimpleX exposes no presence information, so no online dot is shown.
    online: false,
    unread: preview.unreadCount,
    muted: preview.muted,
    pinned: preview.pinned,
    isGroup: isGroup,
    canSend: ready,
    needsAccept: needsAccept,
    requestId: preview.embeddedContactRequestId,
    avatarBytes: preview.avatarImage,
    fullName: preview.fullName,
    bio: preview.shortDescr.isNotEmpty
        ? preview.shortDescr
        : preview.description,
    memberCount: members,
    quantumResistant: preview.quantumResistant,
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

  /// Files we already asked the core to download; the status flips to
  /// `rcvAccepted`, but a retry guard keeps a failed request from looping.
  final Set<int> _requestedFiles = {};

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

  /// Matches `MAX_IMAGE_SIZE_AUTO_RCV` (255 KB * 2) from the official client:
  /// small images are fetched without asking, so the bubble can paint the real
  /// file instead of the inline thumbnail.
  static const int _maxAutoReceiveImageSize = 522240;

  void _autoReceiveImages(
    ChatCore core,
    List<Map<String, dynamic>> raw,
  ) {
    for (final item in raw) {
      final file = item['file'];
      if (file is! Map) continue;
      final status = file['fileStatus'];
      if (status is! Map || status['type'] != 'rcvInvitation') continue;
      final content = item['content'];
      final msgContent = content is Map ? content['msgContent'] : null;
      if (msgContent is! Map || msgContent['type'] != 'image') continue;
      final id = file['fileId'];
      final size = file['fileSize'];
      if (id is! int || size is! int || size > _maxAutoReceiveImageSize) {
        continue;
      }
      if (!_requestedFiles.add(id)) continue;
      unawaited(core.receiveFile(id));
    }
  }

  Future<List<MessageItem>> _fetch(ChatCore core, String chatRef) async {
    final raw = await core.getChatMessages(chatRef);
    _autoReceiveImages(core, raw);
    final chats = ref.read(chatsProvider).valueOrNull;
    String? chatName;
    for (final chat in chats ?? const <ChatSummary>[]) {
      if (chat.id == chatRef) chatName = chat.name;
    }
    return buildTimeline(
      raw,
      now: ref.read(clockProvider)(),
      chatName: chatName,
    );
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
  Future<bool> send(
    String text, {
    int? quotedItemId,
    MessageReply? reply,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final now = ref.read(clockProvider)();
    final optimistic = MessageItem(
      text: trimmed,
      time: DateFormat.Hm().format(now),
      timestamp: now,
      outgoing: true,
      status: MessageStatus.sending,
      reply: reply,
    );
    final current = state.valueOrNull ?? const <MessageItem>[];
    state = AsyncData([...current, optimistic]);

    final core = ref.read(chatCoreProvider);
    unawaited(_paintOutgoingMarkdown(core, trimmed));
    final ok = await core.sendMessage(
      arg,
      trimmed,
      quotedItemId: quotedItemId,
    );
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

  /// Paints the optimistic bubble with the core's own markdown spans before
  /// the timeline refetch replaces it; the core parses the same text for the
  /// stored chat item (`chat_parse_markdown`, `Mobile.hs:222`).
  Future<void> _paintOutgoingMarkdown(ChatCore core, String text) async {
    List<MessageSpan>? spans;
    try {
      spans = await core.parseMarkdown(text);
    } catch (_) {
      return;
    }
    if (spans == null || _disposed) return;
    final updated = [...state.valueOrNull ?? const <MessageItem>[]];
    for (var i = updated.length - 1; i >= 0; i--) {
      final item = updated[i];
      if (item.outgoing && item.spans == null && item.text == text) {
        updated[i] = item.copyWith(spans: spans);
        state = AsyncData(updated);
        return;
      }
    }
  }

  /// Replaces the text of one of my messages (`/_update item`). The refetch
  /// that `chatItemUpdated` schedules replaces the optimistic row with the
  /// core's item, including its fresh markdown spans.
  Future<bool> editMessage(int itemId, String text) async {
    final core = ref.read(chatCoreProvider);
    final ok = await core.editMessage(arg, itemId, text);
    if (!ok || _disposed) return ok;
    final updated = <MessageItem>[];
    for (final item in state.valueOrNull ?? const <MessageItem>[]) {
      updated.add(
        item.itemId == itemId
            ? item.copyWith(text: text, edited: true, clearSpans: true)
            : item,
      );
    }
    state = AsyncData(updated);
    return true;
  }

  /// Deletes one message (`/_delete item`).
  Future<bool> deleteMessage(int itemId, {required bool forEveryone}) async {
    final core = ref.read(chatCoreProvider);
    final ok = await core.deleteMessage(
      arg,
      itemId,
      forEveryone: forEveryone,
    );
    if (!ok || _disposed) return ok;
    final updated = [
      for (final item in state.valueOrNull ?? const <MessageItem>[])
        if (item.itemId != itemId) item,
    ];
    state = AsyncData(updated);
    return true;
  }

  /// Adds the emoji, or removes it when I already reacted with it.
  Future<bool> toggleReaction(int itemId, String emoji) async {
    final wireEmoji = emoji == '❤️' ? '❤' : emoji;
    final current = state.valueOrNull ?? const <MessageItem>[];
    var add = true;
    for (final item in current) {
      if (item.itemId != itemId) continue;
      add = !item.reactions.any((r) => r.emoji == wireEmoji && r.mine);
      break;
    }
    final core = ref.read(chatCoreProvider);
    final ok = await core.setReaction(arg, itemId, wireEmoji, add: add);
    if (!ok || _disposed) return ok;
    final updated = <MessageItem>[];
    for (final item in state.valueOrNull ?? const <MessageItem>[]) {
      updated.add(
        item.itemId == itemId
            ? item.copyWith(
                reactions: _applyReaction(item.reactions, wireEmoji, add),
              )
            : item,
      );
    }
    state = AsyncData(updated);
    return true;
  }
}

List<MessageReaction> _applyReaction(
  List<MessageReaction> current,
  String emoji,
  bool add,
) {
  final result = <MessageReaction>[];
  var found = false;
  for (final reaction in current) {
    if (reaction.emoji != emoji) {
      result.add(reaction);
      continue;
    }
    found = true;
    if (add) {
      result.add(reaction.copyWith(count: reaction.count + 1, mine: true));
    } else if (reaction.count > 1) {
      result.add(reaction.copyWith(count: reaction.count - 1, mine: false));
    }
  }
  if (add && !found) result.add(MessageReaction(emoji: emoji, mine: true));
  return result;
}

// ===== Timeline mapping =====

/// Maps raw `/_get chat` items to bubble-ready rows, inserting day separators
/// and grouping consecutive messages.
List<MessageItem> buildTimeline(
  List<Map<String, dynamic>> rawItems, {
  DateTime? now,
  String? chatName,
}) {
  final reference = now ?? DateTime.now();
  final parsed = <(int, UiMessage, String?)>[];
  for (var index = 0; index < rawItems.length; index++) {
    try {
      final item = Map<String, dynamic>.from(rawItems[index]);
      final message = parseChatItem(item);
      if (message != null) parsed.add((index, message, _senderFrom(item)));
    } catch (_) {
      // A single malformed item must not blank out the conversation.
    }
  }
  // Dart's sort is not stable and bursts of items share a timestamp, so the
  // core order breaks the tie; otherwise the history shuffles itself.
  parsed.sort((a, b) {
    final at = a.$2.time ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = b.$2.time ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byTime = at.compareTo(bt);
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });

  final timeline = <MessageItem>[];
  DateTime? lastDay;
  for (final (_, message, sender) in parsed) {
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
    timeline.add(_toItem(message, sender, chatName));
  }
  _mergeAlbums(timeline);
  _applyGrouping(timeline);
  return timeline;
}

/// Telegram albums hold up to ten photos/videos in one bubble. The core sends
/// every image as its own chat item (`/_send` takes an array and answers with
/// one item per image), so neighbouring items are folded back together here.
/// A minimal gap keeps photos that were sent one by one as separate messages.
const _albumMaxCount = 10;
const _albumWindow = Duration(seconds: 3);

void _mergeAlbums(List<MessageItem> timeline) {
  if (timeline.length < 2) return;
  final merged = <MessageItem>[];
  for (final item in timeline) {
    final base = merged.isEmpty ? null : merged.last;
    if (_isAlbumTile(item) &&
        base != null &&
        _isAlbumTile(base) &&
        base.album.length < _albumMaxCount &&
        base.outgoing == item.outgoing &&
        base.sender == item.sender &&
        _withinAlbumWindow(base, item)) {
      merged[merged.length - 1] = _appendAlbumTile(base, item);
    } else {
      merged.add(item);
    }
  }
  timeline
    ..clear()
    ..addAll(merged);
}

/// Only plain photos and videos join an album: stickers, round videos and
/// files stay on their own (`GroupedMedia` in Telegram groups photos and
/// videos only).
bool _isAlbumTile(MessageItem item) {
  if (item.isSystem || item.isDateSeparator) return false;
  if (item.imageBytes == null && item.imagePath == null) return false;
  final label = item.mediaLabel;
  if (label == null) return false;
  return label.startsWith('Photo') || label.startsWith('Video');
}

bool _withinAlbumWindow(MessageItem first, MessageItem second) {
  final a = first.timestamp;
  final b = second.timestamp;
  if (a == null || b == null) return false;
  return b.difference(a).abs() <= _albumWindow;
}

MessageItem _appendAlbumTile(MessageItem base, MessageItem tile) {
  final caption = tile.text.isEmpty
      ? base.text
      : base.text.isEmpty
      ? tile.text
      : '${base.text}\n${tile.text}';
  return base.copyWith(
    // The first tile is the base item itself; every later one is appended, so
    // the mosaic always carries all photos of the batch.
    album: [
      if (base.album.isEmpty) AlbumTile.of(base),
      ...base.album,
      AlbumTile.of(tile),
    ],
    text: caption,
    time: tile.time,
    timestamp: tile.timestamp ?? base.timestamp,
    itemId: tile.itemId ?? base.itemId,
    status: base.status == MessageStatus.failed || tile.status == MessageStatus.failed
        ? MessageStatus.failed
        : tile.status,
    reactions: _mergeReactions(base.reactions, tile.reactions),
    transferStatus: tile.transferStatus,
    transferProgress: tile.transferProgress,
    transferTotal: tile.transferTotal,
    mediaLabel: base.mediaLabel,
    imageBytes: tile.imageBytes,
    imagePath: tile.imagePath,
    isVideo: tile.isVideo,
  );
}

List<MessageReaction> _mergeReactions(
  List<MessageReaction> current,
  List<MessageReaction> next,
) {
  if (next.isEmpty) return current;
  if (current.isEmpty) return next;
  final result = [...current];
  for (final reaction in next) {
    final index = result.indexWhere((r) => r.emoji == reaction.emoji);
    if (index < 0) {
      result.add(reaction);
    } else {
      final existing = result[index];
      result[index] = existing.copyWith(
        count: existing.count + reaction.count,
        mine: existing.mine || reaction.mine,
      );
    }
  }
  return result;
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

MessageItem _toItem(UiMessage message, String? sender, String? chatName) {
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
    itemId: message.itemId,
    reactions: [
      for (final reaction in message.reactions)
        MessageReaction(
          emoji: reaction.emoji,
          count: reaction.count,
          mine: reaction.mine,
        ),
    ],
    imageBytes: image?.bytes,
    imagePath: image?.filePath,
    isVideo: image?.isVideo ?? false,
    // The core rewrites `fileStatus` in the DB on every progress event, so a
    // timeline refetch is enough to animate the ring.
    transferStatus: image?.fileStatusType ?? message.fileStatusType,
    transferProgress: image?.transferProgress ?? message.transferProgress,
    transferTotal: image?.transferTotal ?? message.transferTotal,
    // Audio attachments keep their own "Voice message" row for now.
    fileName: message.audio == null ? message.fileName : null,
    fileSize: message.audio == null ? message.fileSize : null,
    fileId: message.fileId,
    filePath: message.filePath,
    reply: quoted == null
        ? null
        : MessageReply(
            author: _quotedAuthor(quoted, sender, chatName),
            text: quoted.text,
            spans: quoted.formattedText,
          ),
    spans: message.formattedText,
    edited: message.edited,
    editable: message.editable,
    deletable: message.deletable,
    forwarded: message.forwarded,
    forwardedFrom: message.forwardedFrom,
  );
}

/// Mirrors `CIQuote.sender`: outgoing quotes belong to the account, group
/// quotes to the member carried in `chatDir`, direct quotes to the peer.
String _quotedAuthor(
  QuotedMessage quoted,
  String? sender,
  String? chatName,
) {
  if (quoted.chatDir.endsWith('Snd')) return 'You';
  if (quoted.chatDir.startsWith('group')) {
    if (quoted.senderName.isNotEmpty) return quoted.senderName;
    return sender ?? chatName ?? '';
  }
  return chatName ?? sender ?? '';
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
