import 'dart:typed_data';

import '../../../data/formatted_text.dart';

class UiMessage {
  final String key;
  final String text;
  final bool fromMe;
  final String timeStr;
  final String status;
  final bool isSystem;
  final List<UiImage> images;
  final DateTime? time;
  final int? itemId;
  final QuotedMessage? quoted;
  final AudioItem? audio;
  final String? fileName;
  final int? fileSize;
  final String? filePath;
  final int? fileId;
  final String? fileStatusType;
  final int? transferProgress;
  final int? transferTotal;
  final List<UiReaction> reactions;

  /// Spans from `ChatItem.formattedText`; null when the text is plain or the
  /// parser had to rewrite it (prefixes for voice/report items).
  final List<MessageSpan>? formattedText;

  /// `CIMeta.itemEdited`: the message text was changed after sending.
  final bool edited;

  /// `CIMeta.editable`: sent, under 24h, not forwarded, not deleted.
  final bool editable;

  /// `CIMeta.deletable`: the core will broadcast the deletion to the peer.
  final bool deletable;

  /// `CIMeta.itemForwarded`: renders the "Forwarded from …" header.
  final bool forwarded;
  final String? forwardedFrom;

  const UiMessage({
    required this.key,
    required this.text,
    required this.fromMe,
    required this.timeStr,
    required this.status,
    required this.isSystem,
    required this.images,
    required this.time,
    this.itemId,
    this.quoted,
    this.audio,
    this.fileName,
    this.fileSize,
    this.filePath,
    this.fileId,
    this.fileStatusType,
    this.transferProgress,
    this.transferTotal,
    this.reactions = const [],
    this.formattedText,
    this.edited = false,
    this.editable = false,
    this.deletable = false,
    this.forwarded = false,
    this.forwardedFrom,
  });
}

class UiReaction {
  final String emoji;
  final int count;
  final bool mine;

  const UiReaction({required this.emoji, this.count = 1, this.mine = false});
}

class UiImage {
  final Uint8List? bytes;
  final String? filePath;
  final int? fileId;
  final int? fileSize;
  final String? fileStatusType;
  final int? transferProgress;
  final int? transferTotal;
  final bool isVideo;
  final bool isCircle;
  final bool isSticker;
  final bool isWebm;
  final int? durationSec;

  const UiImage({
    this.bytes,
    this.filePath,
    this.fileId,
    this.fileSize,
    this.fileStatusType,
    this.transferProgress,
    this.transferTotal,
    this.isVideo = false,
    this.isCircle = false,
    this.isSticker = false,
    this.isWebm = false,
    this.durationSec,
  });

  bool get hasFullImage => filePath != null;
}

class AudioItem {
  final String title;
  final String? filePath;
  final int? fileId;
  final String? fileStatusType;
  final int? fileSize;
  final int? transferProgress;
  final int? transferTotal;

  const AudioItem({
    required this.title,
    required this.filePath,
    this.fileId,
    this.fileStatusType,
    this.fileSize,
    this.transferProgress,
    this.transferTotal,
  });
}

class AudioNowPlaying {
  final String filePath;
  final String title;

  const AudioNowPlaying({
    required this.filePath,
    required this.title,
  });
}

class QuotedMessage {
  final String text;

  /// Group member name carried by `chatDir.groupMember` for group replies.
  final String senderName;

  /// `directSnd`, `directRcv`, `groupSnd`, `groupRcv`, ... — decides who the
  /// quote is attributed to, exactly like `CIQuote.sender` upstream.
  final String chatDir;
  final int? itemId;

  /// `CIQuote.formattedText`.
  final List<MessageSpan>? formattedText;

  const QuotedMessage({
    required this.text,
    this.senderName = '',
    this.chatDir = '',
    this.itemId,
    this.formattedText,
  });
}

class PreviewPayload {
  final Uint8List bytes;
  final String mime;

  const PreviewPayload({required this.bytes, required this.mime});
}

class CircleVideoResult {
  final String filePath;
  final Uint8List previewBytes;
  final int durationSec;

  const CircleVideoResult({
    required this.filePath,
    required this.previewBytes,
    required this.durationSec,
  });
}

class SendResult {
  final bool ok;
  final String? error;

  const SendResult({required this.ok, this.error});
}
