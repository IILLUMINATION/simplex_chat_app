import 'dart:typed_data';

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
    this.avatarBytes,
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
  final Uint8List? avatarBytes;
}

class MessageReply {
  const MessageReply({required this.author, required this.text});

  final String author;
  final String text;
}

enum MessageStatus { none, sending, sent, delivered, read, failed }

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
    this.isSystem = false,
    this.isDateSeparator = false,
  });

  final String text;
  final String time;
  final DateTime? timestamp;
  final bool outgoing;
  final bool firstInGroup;
  final bool lastInGroup;
  final String? sender;
  final MessageReply? reply;
  final MessageStatus status;
  final String? mediaLabel;

  /// Inline preview bytes delivered by the core for photos/videos.
  final Uint8List? imageBytes;

  /// Local path once the full file has been downloaded.
  final String? imagePath;
  final bool isSystem;

  /// Pseudo-item that starts a new day; [text] holds the pill label.
  final bool isDateSeparator;

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
    bool? isSystem,
    bool? isDateSeparator,
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
    isSystem: isSystem ?? this.isSystem,
    isDateSeparator: isDateSeparator ?? this.isDateSeparator,
  );
}
