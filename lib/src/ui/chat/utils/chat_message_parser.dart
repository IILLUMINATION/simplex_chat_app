import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;

import '../models/chat_message_models.dart';

UiMessage? parseChatItem(Map<String, dynamic> msg) {
  final chatDir = msg['chatDir'] as Map<String, dynamic>?;
  final dirType = chatDir?['type'] as String? ?? '';
  final fromMe = dirType.endsWith('Snd');

  final meta = msg['meta'] as Map<String, dynamic>?;
  final statusObj = meta?['itemStatus'];
  final status = statusObj is Map ? (statusObj['type'] as String? ?? '') : '';
  final itemText = meta?['itemText'] as String?;
  final tsStr = meta?['itemTs'] as String?;
  final msgKey = '${dirType}_${tsStr ?? ''}_${itemText ?? ''}';
  String timeStr = '';
  DateTime? time;
  if (tsStr != null) {
    try {
      time = DateTime.parse(tsStr).toLocal();
      timeStr = DateFormat.Hm().format(time);
    } catch (_) {}
  }

  final content = msg['content'] as Map<String, dynamic>?;
  final contentType = content?['type'] as String?;
  if (contentType == 'chatBanner') {
    return UiMessage(
      key: 'banner_$tsStr',
      text: itemText ?? 'Chat started',
      fromMe: false,
      timeStr: '',
      status: '',
      isSystem: true,
      images: const [],
      time: time,
    );
  }

  if (contentType == 'sndMsgContent' || contentType == 'rcvMsgContent') {
    final msgContent = content?['msgContent'] as Map<String, dynamic>?;
    final msgType = msgContent?['type'] as String?;
    final text = msgContent?['text'] as String? ?? '';
    final imageData = msgContent?['image'] as String?;
    final durationSec = msgContent?['duration'] as int?;
    final images = <UiImage>[];
    final fileObj = msg['file'] as Map<String, dynamic>?;
    final fileSource = fileObj?['fileSource'] as Map<String, dynamic>?;
    final filePath = fileSource?['filePath'] as String?;
    final fileId = fileObj?['fileId'] as int?;
    final fileSize = fileObj?['fileSize'] as int?;
    final fileStatus = fileObj?['fileStatus'] as Map<String, dynamic>?;
    final fileStatusType = fileStatus?['type'] as String?;
    final fileName = fileObj?['fileName'] as String?;
    final isCircle = (fileName != null && fileName.startsWith('circle_'));
    final isSticker = fileName != null && fileName.startsWith('st__');
    final isWebm = fileName != null && fileName.toLowerCase().endsWith('.webm');
    final audioItem = parseAudio(fileName, filePath);
    final decoded = decodeImage(imageData);
    final hasLocalFile = filePath != null && File(filePath).existsSync();
    if (msgType == 'video') {
      images.add(UiImage(
        filePath: hasLocalFile ? filePath : null,
        bytes: decoded,
        fileId: fileId,
        fileSize: fileSize,
        fileStatusType: fileStatusType,
        isVideo: true,
        isCircle: isCircle,
        isSticker: isSticker,
        isWebm: isWebm,
        durationSec: durationSec,
      ));
    } else if (msgType == 'image') {
      images.add(UiImage(
        filePath: hasLocalFile ? filePath : null,
        bytes: decoded,
        fileId: fileId,
        fileSize: fileSize,
        fileStatusType: fileStatusType,
        isSticker: isSticker,
        isWebm: isWebm,
      ));
    } else if (msgType != 'file') {
      if (hasLocalFile) {
        images.add(UiImage(
          filePath: filePath,
          fileId: fileId,
          fileSize: fileSize,
          fileStatusType: fileStatusType,
          isVideo: false,
        ));
      } else if (decoded != null) {
        images.add(UiImage(
          bytes: decoded,
          fileId: fileId,
          fileSize: fileSize,
          fileStatusType: fileStatusType,
          isVideo: false,
        ));
      }
    }
    if ((msgType == 'image' || msgType == 'video') &&
        isSticker &&
        images.isEmpty) {
      images.add(UiImage(
        filePath: hasLocalFile ? filePath : null,
        bytes: decoded,
        fileId: fileId,
        fileSize: fileSize,
        fileStatusType: fileStatusType,
        isVideo: msgType == 'video',
        isSticker: true,
        isWebm: isWebm,
        durationSec: durationSec,
      ));
    }
    if (msgType == 'file' && audioItem != null) {
      return UiMessage(
        key: msgKey,
        text: '',
        fromMe: fromMe,
        timeStr: timeStr,
        status: status,
        isSystem: false,
        images: const [],
        time: time,
        audio: audioItem,
        fileName: fileName,
        fileSize: fileSize,
        filePath: filePath,
      );
    }
    String display = text;
    if (msgType == 'image') {
      display = text;
    } else if (msgType == 'video') {
      display = isCircle ? '' : text;
    } else if (msgType == 'voice') {
      display = text.isNotEmpty ? '🎤 $text' : '';
    } else if (msgType == 'file') {
      display = text.isNotEmpty ? text : '';
    } else if (msgType == 'link') {
      display = text;
    } else if (msgType == 'report') {
      display = text.isNotEmpty ? '🚩 $text' : '';
    } else if (msgType == 'chat') {
      display = text.isNotEmpty ? '💬 $text' : '';
    } else if (msgType == 'unknown') {
      display = text.isNotEmpty ? text : '[Unsupported]';
    }
    return UiMessage(
      key: msgKey,
      text: display.isNotEmpty ? display : (itemText ?? ''),
      fromMe: fromMe,
      timeStr: timeStr,
      status: status,
      isSystem: false,
      images: images,
      time: time,
      fileName: msgType == 'file' ? fileName : null,
      fileSize: msgType == 'file' ? fileSize : null,
      filePath: msgType == 'file' ? filePath : null,
    );
  }

  if (contentType != null) {
    final label = itemText ?? contentType;
    return UiMessage(
      key: 'other_${tsStr ?? ''}',
      text: label,
      fromMe: false,
      timeStr: '',
      status: '',
      isSystem: true,
      images: const [],
      time: time,
    );
  }

  if (itemText != null && itemText.isNotEmpty) {
    return UiMessage(
      key: msgKey,
      text: itemText,
      fromMe: fromMe,
      timeStr: timeStr,
      status: status,
      isSystem: false,
      images: const [],
      time: time,
    );
  }

  return null;
}

AudioItem? parseAudio(String? fileName, String? filePath) {
  if (fileName == null) return null;
  final lower = fileName.toLowerCase();
  const exts = [
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.opus',
    '.flac'
  ];
  final isAudio = exts.any(lower.endsWith);
  if (!isAudio) return null;
  return AudioItem(title: fileName, filePath: filePath);
}

bool closeInTime(DateTime? a, DateTime? b, Duration delta) {
  if (a == null || b == null) return false;
  return (a.difference(b).abs() <= delta);
}

Uint8List? decodeImage(String? dataUri) {
  if (dataUri == null || dataUri.isEmpty) return null;
  final marker = 'base64,';
  final idx = dataUri.indexOf(marker);
  if (idx == -1) return null;
  final b64 = dataUri.substring(idx + marker.length);
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

String guessMime(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

PreviewPayload makePreview(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return PreviewPayload(bytes: bytes, mime: 'image/jpeg');
    }
    final resized = img.copyResize(decoded, width: 192);
    final jpg = img.encodeJpg(resized, quality: 60);
    return PreviewPayload(bytes: Uint8List.fromList(jpg), mime: 'image/jpeg');
  } catch (_) {
    return PreviewPayload(bytes: bytes, mime: 'image/jpeg');
  }
}

const int maxAutoReceiveImageSize = 522240; // 255KB * 2 (TangleX iOS)

Uint8List prepareCirclePreview(Uint8List input) {
  try {
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;
    final size = decoded.width < decoded.height
        ? decoded.width
        : decoded.height;
    final offsetX = (decoded.width - size) ~/ 2;
    final offsetY = (decoded.height - size) ~/ 2;
    final cropped = img.copyCrop(
      decoded,
      x: offsetX,
      y: offsetY,
      width: size,
      height: size,
    );
    final resized = img.copyResize(cropped, width: 320, height: 320);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
  } catch (_) {
    return input;
  }
}

PreviewPayload prepareStickerPreview(Uint8List input) {
  try {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      return PreviewPayload(bytes: input, mime: 'image/jpeg');
    }
    final resized = img.copyResize(decoded, width: 160);
    final jpg = Uint8List.fromList(img.encodeJpg(resized, quality: 60));
    return PreviewPayload(bytes: jpg, mime: 'image/jpeg');
  } catch (_) {
    return PreviewPayload(bytes: input, mime: 'image/jpeg');
  }
}

PreviewPayload compressPreview(PreviewPayload input, {int maxBytes = 35000}) {
  if (input.bytes.length <= maxBytes) return input;
  try {
    final decoded = img.decodeImage(input.bytes);
    if (decoded == null) return PreviewPayload(bytes: tinyPreview(), mime: 'image/jpeg');
    int size = 140;
    int quality = 55;
    Uint8List out = input.bytes;
    while (out.length > maxBytes && size >= 64) {
      final resized = img.copyResize(decoded, width: size);
      out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      size -= 16;
      quality = (quality - 5).clamp(30, 90);
    }
    return PreviewPayload(bytes: out, mime: 'image/jpeg');
  } catch (_) {
    return PreviewPayload(bytes: tinyPreview(), mime: 'image/jpeg');
  }
}

Uint8List tinyPreview() {
  final img1 = img.Image(width: 2, height: 2);
  img.fill(img1, color: img.ColorRgba8(136, 136, 136, 255));
  return Uint8List.fromList(img.encodeJpg(img1, quality: 50));
}

String chatRefFromInfo(Map<String, dynamic> chatInfo) {
  final type = chatInfo['type'] as String?;
  if (type == 'direct') {
    final contact = chatInfo['contact'] as Map<String, dynamic>?;
    final contactId = contact?['contactId'] as int?;
    if (contactId != null) return '@$contactId';
  } else if (type == 'group') {
    final group = chatInfo['group'] as Map<String, dynamic>?;
    final groupId = group?['groupId'] as int?;
    if (groupId != null) return '#$groupId';
  } else if (type == 'contactRequest') {
    final req = chatInfo['contactRequest'] as Map<String, dynamic>?;
    final contactId = req?['contactId_'] as int?;
    if (contactId != null) return '<@$contactId';
  } else if (type == 'contactConnection') {
    final conn = chatInfo['contactConnection'] as Map<String, dynamic>?;
    final connId = conn?['connId'] as int?;
    if (connId != null) return '<@$connId';
  }
  return '';
}

String slugify(String input) {
  final lower = input.toLowerCase();
  final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  return cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  String firstChar(String s) =>
      String.fromCharCode(s.runes.isNotEmpty ? s.runes.first : 63);
  if (parts.length == 1) {
    return firstChar(parts.first).toUpperCase();
  }
  final first = firstChar(parts.first).toUpperCase();
  final last = firstChar(parts.last).toUpperCase();
  return '$first$last';
}

String formatDuration(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(1, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
