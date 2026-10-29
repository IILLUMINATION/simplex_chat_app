import 'dart:typed_data';

import '../data/formatted_text.dart';

/// One row in the chat list — the UI-side view of a SimpleX chat.
class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.name,
    required this.preview,
    required this.time,
    this.subtitle,
    this.previewAuthor,
    this.unread = 0,
    this.pinned = false,
    this.muted = false,
    this.online = false,
    this.verified = false,
    this.isGroup = false,
    this.canSend = true,
    this.needsAccept = false,
    this.requestId,
    this.avatarBytes,
    this.fullName = '',
    this.bio = '',
    this.memberCount,
    this.quantumResistant,
  });

  /// Chat reference used by the core: `@12` for contacts, `#7` for groups.
  final String id;
  final String name;
  final String preview;
  final String time;
  final String? subtitle;
  final String? previewAuthor;
  final int unread;
  final bool pinned;
  final bool muted;
  final bool online;
  final bool verified;
  final bool isGroup;

  /// The core can deliver messages to this peer right now.
  final bool canSend;

  /// Incoming contact request waiting for [requestId] to be accepted.
  final bool needsAccept;
  final int? requestId;
  final Uint8List? avatarBytes;

  /// SimpleX `profile.fullName` (second name line).
  final String fullName;

  /// SimpleX `profile.shortDescr` (bio).
  final String bio;

  /// `groupSummary.currentMembers`; null for direct chats.
  final int? memberCount;

  /// `activeConn.connPQEnabled`; null when the connection is not ready.
  final bool? quantumResistant;
}

class MessageReply {
  const MessageReply({required this.author, required this.text, this.spans});

  final String author;

  /// Raw quote text as the core stores it (markdown source included).
  final String text;

  /// `CIQuote.formattedText`, when the quoted item carried formatting.
  final List<MessageSpan>? spans;

  String get displayText =>
      spans == null ? text : spansDisplayText(spans!);
}

/// One emoji reaction on a chat item, as rendered under the bubble.
class MessageReaction {
  const MessageReaction({
    required this.emoji,
    this.count = 1,
    this.mine = false,
  });

  final String emoji;
  final int count;
  final bool mine;

  MessageReaction copyWith({int? count, bool? mine}) => MessageReaction(
    emoji: emoji,
    count: count ?? this.count,
    mine: mine ?? this.mine,
  );
}

enum MessageStatus { none, sending, sent, delivered, read, failed }

/// One tile of a Telegram-style album. SimpleX sends every photo as its own
/// chat item, so the timeline merges neighbouring items into [MessageItem.album]
/// and keeps each item's bytes and transfer state here.
class AlbumTile {
  const AlbumTile({
    this.bytes,
    this.path,
    this.isVideo = false,
    this.transferStatus,
    this.transferProgress,
    this.transferTotal,
    this.itemId,
  });

  AlbumTile.of(MessageItem message)
    : bytes = message.imageBytes,
      path = message.imagePath,
      isVideo = message.isVideo,
      transferStatus = message.transferStatus,
      transferProgress = message.transferProgress,
      transferTotal = message.transferTotal,
      itemId = message.itemId;

  final Uint8List? bytes;
  final String? path;
  final bool isVideo;
  final String? transferStatus;
  final int? transferProgress;
  final int? transferTotal;
  final int? itemId;

  bool get isTransferring =>
      transferStatus == 'sndTransfer' || transferStatus == 'rcvTransfer';

  double? get transferFraction {
    if (!isTransferring) return null;
    final total = transferTotal;
    final done = transferProgress;
    if (total == null || total <= 0 || done == null) return null;
    return (done / total).clamp(0.0, 1.0);
  }
}

/// One attachment staged in the composer, e.g. pasted from the clipboard.
///
/// Telegram stages pasted media in the send preview before the message goes
/// out (`HistoryWidget::confirmSendingFiles` → send-media preview); the
/// composer keeps the same list here until the send button fires.
class ComposerAttachment {
  const ComposerAttachment({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.isImage,
    this.previewBytes,
    this.previewMime,
  });

  final String path;
  final String name;
  final int sizeBytes;

  /// Decoded and resized with `makePreview`; an image that cannot be decoded
  /// is staged as a document, the way Telegram keeps unreadable photos as
  /// files.
  final bool isImage;
  final Uint8List? previewBytes;
  final String? previewMime;
}

/// One chat item rendered in the conversation.
class MessageItem {
  const MessageItem({
    required this.text,
    required this.time,
    this.timestamp,
    this.outgoing = false,
    this.firstInGroup = true,
    this.lastInGroup = true,
    this.sender,
    this.reply,
    this.status = MessageStatus.none,
    this.mediaLabel,
    this.imageBytes,
    this.imagePath,
    this.isVideo = false,
    this.transferStatus,
    this.transferProgress,
    this.transferTotal,
    this.fileName,
    this.fileSize,
    this.fileId,
    this.filePath,
    this.isSystem = false,
    this.isDateSeparator = false,
    this.itemId,
    this.reactions = const [],
    this.album = const [],
    this.spans,
    this.edited = false,
    this.editable = false,
    this.deletable = false,
    this.forwarded = false,
    this.forwardedFrom,
  });

  final String text;

  /// `ChatItem.formattedText` from the core, the same spans the official
  /// clients paint. Null means the message has no markdown.
  final List<MessageSpan>? spans;

  /// `CIMeta.itemEdited`: the bubble shows "edited" after the time.
  final bool edited;

  /// `CIMeta.editable`: the core accepts an `/_update item` for this message.
  final bool editable;

  /// `CIMeta.deletable`: the core will tell the peer about the deletion.
  final bool deletable;

  /// `CIMeta.itemForwarded`: the bubble shows "Forwarded from …" above the
  /// text, like Telegram's forwarded header.
  final bool forwarded;

  /// The source chat name from `CIForwardedFrom.chatName`; null when the core
  /// only knows it was forwarded somewhere.
  final String? forwardedFrom;

  /// What the bubble shows: formatted spans when the core sent them, the raw
  /// text otherwise.
  String get displayText =>
      spans == null ? text : spansDisplayText(spans!);
  final String time;
  final DateTime? timestamp;
  final bool outgoing;
  final bool firstInGroup;
  final bool lastInGroup;
  final String? sender;
  final MessageReply? reply;
  final MessageStatus status;
  final String? mediaLabel;

  /// Core id used for replies and reactions on this item.
  final int? itemId;
  final List<MessageReaction> reactions;

  /// Inline preview bytes delivered by the core for photos/videos.
  final Uint8List? imageBytes;

  /// Local path once the full file has been downloaded.
  final String? imagePath;

  /// Video files need a player; the bubble keeps the inline preview instead of
  /// decoding them through `Image.file`.
  final bool isVideo;

  /// Raw `fileStatus.type` from the core. `sndTransfer`/`rcvTransfer` mean the
  /// file is still moving and the bubble shows Telegram's radial progress.
  final String? transferStatus;

  /// Bytes transferred so far (`sndProgress`/`rcvProgress`).
  final int? transferProgress;
  final int? transferTotal;

  /// 0..1 while a transfer runs; null once the file is complete (or when the
  /// core reports no byte counters).
  double? get transferFraction {
    if (!isTransferring) return null;
    final total = transferTotal;
    final done = transferProgress;
    if (total == null || total <= 0 || done == null) return null;
    return (done / total).clamp(0.0, 1.0);
  }

  bool get isTransferring =>
      transferStatus == 'sndTransfer' || transferStatus == 'rcvTransfer';

  /// Document attachment (`msgContent.type == 'file'`). Photos, videos and
  /// voice notes deliver their payload through [imageBytes]/[imagePath].
  final String? fileName;
  final int? fileSize;

  /// Core `fileId`, needed by `/freceive <fileId>` to accept a download.
  final int? fileId;

  /// On-disk path once the core has the file (sent, or received).
  final String? filePath;

  bool get isDocument => fileName != null;

  final bool isSystem;

  /// Pseudo-item that starts a new day; [text] holds the pill label.
  final bool isDateSeparator;

  /// Photos/videos merged into one Telegram-style mosaic. Empty for a single
  /// photo, which keeps the plain [_MediaPreview] path. The item itself keeps
  /// the last tile's time and id, so reactions and replies still target the
  /// freshest chat item of the batch.
  final List<AlbumTile> album;

  MessageItem copyWith({
    String? text,
    String? time,
    DateTime? timestamp,
    bool? outgoing,
    bool? firstInGroup,
    bool? lastInGroup,
    String? sender,
    MessageReply? reply,
    MessageStatus? status,
    String? mediaLabel,
    Uint8List? imageBytes,
    String? imagePath,
    bool? isVideo,
    String? transferStatus,
    int? transferProgress,
    int? transferTotal,
    String? fileName,
    int? fileSize,
    int? fileId,
    String? filePath,
    bool? isSystem,
    bool? isDateSeparator,
    int? itemId,
    List<MessageReaction>? reactions,
    List<AlbumTile>? album,
    List<MessageSpan>? spans,
    bool clearSpans = false,
    bool? edited,
    bool? editable,
    bool? deletable,
    bool? forwarded,
    String? forwardedFrom,
  }) => MessageItem(
    text: text ?? this.text,
    time: time ?? this.time,
    timestamp: timestamp ?? this.timestamp,
    outgoing: outgoing ?? this.outgoing,
    firstInGroup: firstInGroup ?? this.firstInGroup,
    lastInGroup: lastInGroup ?? this.lastInGroup,
    sender: sender ?? this.sender,
    reply: reply ?? this.reply,
    status: status ?? this.status,
    mediaLabel: mediaLabel ?? this.mediaLabel,
    imageBytes: imageBytes ?? this.imageBytes,
    imagePath: imagePath ?? this.imagePath,
    isVideo: isVideo ?? this.isVideo,
    transferStatus: transferStatus ?? this.transferStatus,
    transferProgress: transferProgress ?? this.transferProgress,
    transferTotal: transferTotal ?? this.transferTotal,
    fileName: fileName ?? this.fileName,
    fileSize: fileSize ?? this.fileSize,
    fileId: fileId ?? this.fileId,
    filePath: filePath ?? this.filePath,
    isSystem: isSystem ?? this.isSystem,
    isDateSeparator: isDateSeparator ?? this.isDateSeparator,
    itemId: itemId ?? this.itemId,
    reactions: reactions ?? this.reactions,
    album: album ?? this.album,
    spans: clearSpans ? null : (spans ?? this.spans),
    edited: edited ?? this.edited,
    editable: editable ?? this.editable,
    deletable: deletable ?? this.deletable,
    forwarded: forwarded ?? this.forwarded,
    forwardedFrom: forwardedFrom ?? this.forwardedFrom,
  );
}
