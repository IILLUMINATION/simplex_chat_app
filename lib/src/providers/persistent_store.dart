import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ===== Data Classes =====
class ThemeConfigData {
  const ThemeConfigData({this.theme = 'material', this.mode = 'system'});
  final String theme;
  final String mode;
  ThemeConfigData copyWith({String? theme, String? mode}) =>
      ThemeConfigData(theme: theme ?? this.theme, mode: mode ?? this.mode);
  Map<String, dynamic> toJson() => {'theme': theme, 'mode': mode};
  factory ThemeConfigData.fromJson(Map<String, dynamic> j) => ThemeConfigData(
    theme: j['theme'] as String? ?? 'material',
    mode: j['mode'] as String? ?? 'system',
  );
}

class AppLocaleData {
  const AppLocaleData({this.locale = 'ru'});
  final String locale;
  Map<String, dynamic> toJson() => {'locale': locale};
  factory AppLocaleData.fromJson(Map<String, dynamic> j) =>
      AppLocaleData(locale: j['locale'] as String? ?? 'ru');
}

/// Data class representing a user profile
class ProfileData {
  const ProfileData({
    required this.displayName,
    this.fullName = '',
    this.shortDescr = '',
    this.userId,
    this.agentUserId,
    this.userContactId,
    this.localDisplayName,
  });
  final String displayName;
  final String fullName;
  final String shortDescr;
  final int? userId;
  final String? agentUserId;
  final int? userContactId;
  final String? localDisplayName;

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'fullName': fullName,
    'shortDescr': shortDescr,
    if (userId != null) 'userId': userId,
    if (agentUserId != null) 'agentUserId': agentUserId,
    if (userContactId != null) 'userContactId': userContactId,
    if (localDisplayName != null) 'localDisplayName': localDisplayName,
  };

  factory ProfileData.fromJson(Map<String, dynamic> j) => ProfileData(
    displayName: j['displayName'] as String? ?? '',
    fullName: j['fullName'] as String? ?? '',
    shortDescr: j['shortDescr'] as String? ?? '',
    userId: j['userId'] as int?,
    agentUserId: j['agentUserId'] as String?,
    userContactId: j['userContactId'] as int?,
    localDisplayName: j['localDisplayName'] as String?,
  );
}

/// Parsed chat item from /_get chats response
class ChatPreview {
  const ChatPreview({
    required this.chatRef,
    required this.chatType,
    this.displayName = '',
    this.lastMessage = '',
    this.timestamp,
    this.unreadCount = 0,
    this.chatId,
    this.contactStatus,
    this.contactUsed,
    this.avatarImage,
    this.lastFromMe = false,
  });

  final String chatRef; // e.g. "@1" or "#1"
  final String chatType; // 'contact' or 'group'
  final String displayName;
  final String lastMessage;
  final int? timestamp;
  final int unreadCount;
  final int? chatId;
  final String? contactStatus;
  final bool? contactUsed;
  final Uint8List? avatarImage;
  final bool lastFromMe;

  factory ChatPreview.fromJson(Map<String, dynamic> json) {
    final chatInfo = json['chatInfo'] as Map<String, dynamic>? ?? {};
    final chatType = chatInfo['type'] as String?;
    final contact = chatInfo['contact'] as Map<String, dynamic>?;
    final group = chatInfo['group'] as Map<String, dynamic>?;
    final contactRequest = chatInfo['contactRequest'] as Map<String, dynamic>?;
    final chatItems = json['chatItems'] as List?;

    String lastMsg = '';
    int? ts;
    bool lastFromMe = false;
    if (chatItems != null && chatItems.isNotEmpty) {
      final lastItem = _pickLatestChatItem(chatItems);
      if (lastItem != null) {
        lastMsg = _previewFromChatItem(lastItem);
        if (lastMsg.length > 60) {
          lastMsg = '${lastMsg.substring(0, 57)}...';
        }
        ts = _chatItemTimestamp(lastItem);
        final chatDir = lastItem['chatDir'];
        if (chatDir is Map) {
          final dirType = chatDir['type'] as String?;
          lastFromMe = dirType?.endsWith('Snd') == true;
        }
      }
    }

    String type;
    String name = '';
    int? id;
    String? contactStatus;
    bool? contactUsed;
    Uint8List? avatar;

    if (chatType == 'contactRequest' && contactRequest != null) {
      type = 'contactRequest';
      final profile = contactRequest['profile'] as Map<String, dynamic>?;
      name =
          profile?['displayName'] as String? ??
          contactRequest['localDisplayName'] as String? ??
          '';
      id = contactRequest['contactRequestId'] as int?;
      final img = profile?['image'] as String?;
      avatar = _decodeImage(img);
    } else if (contact != null) {
      type = 'contact';
      name =
          contact['displayName'] as String? ??
          contact['localDisplayName'] as String? ??
          '';
      id = contact['contactId'] as int?;
      contactStatus = contact['contactStatus'] as String?;
      contactUsed = contact['contactUsed'] as bool?;
      final profile = contact['profile'] as Map<String, dynamic>?;
      final img = profile?['image'] as String?;
      avatar = _decodeImage(img);
    } else if (group != null) {
      type = 'group';
      name =
          group['groupName'] as String? ??
          group['localDisplayName'] as String? ??
          '';
      id = group['groupId'] as int?;
    } else if (chatType == 'contactConnection') {
      type = 'contactConnection';
      name = 'Pending connection';
    } else {
      type = 'unknown';
      name = '';
    }

    return ChatPreview(
      chatRef: type == 'contactRequest'
          ? '<@${id ?? '?'}'
          : (type == 'group' ? '#${id ?? '?'}' : '@${id ?? '?'}'),
      chatType: type,
      displayName: name,
      lastMessage: lastMsg,
      timestamp: ts,
      unreadCount: json['unreadCount'] as int? ?? 0,
      chatId: id,
      contactStatus: contactStatus,
      contactUsed: contactUsed,
      avatarImage: avatar,
      lastFromMe: lastFromMe,
    );
  }
}

Map<String, dynamic>? _pickLatestChatItem(List items) {
  Map<String, dynamic>? best;
  int? bestTs;
  for (final raw in items) {
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    final ts = _chatItemTimestamp(item);
    if (best == null) {
      best = item;
      bestTs = ts;
      continue;
    }
    if (ts != null && (bestTs == null || ts > bestTs!)) {
      best = item;
      bestTs = ts;
    }
  }
  return best;
}

int? _chatItemTimestamp(Map<String, dynamic> item) {
  int? ts;
  final raw = item['itemTs'] ?? item['timeStamp'];
  ts = _parseTimestamp(raw);
  if (ts != null) return ts;
  final meta = item['meta'];
  if (meta is Map) {
    ts = _parseTimestamp(meta['itemTs'] ?? meta['timeStamp']);
  }
  return ts;
}

int? _parseTimestamp(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) {
    try {
      final dt = DateTime.parse(value).toLocal();
      return dt.millisecondsSinceEpoch * 1000;
    } catch (_) {
      return null;
    }
  }
  return null;
}

String _previewFromChatItem(Map<String, dynamic> item) {
  final content = item['content'] as Map<String, dynamic>?;
  final contentType = content?['type'] as String?;
  if (contentType == 'chatBanner') {
    final text = content?['text'] as String?;
    if (text != null && text.isNotEmpty) return text;
  }
  if (contentType == 'sndMsgContent' || contentType == 'rcvMsgContent') {
    final msgContent = content?['msgContent'] as Map<String, dynamic>?;
    final msgType = msgContent?['type'] as String?;
    final text = msgContent?['text'] as String?;
    if (text != null && text.trim().isNotEmpty) return text.trim();
    if (msgType == 'image') return 'Фото';
    if (msgType == 'video') return 'Видео';
    if (msgType == 'voice') return 'Голосовое';
    if (msgType == 'sticker') return 'Стикер';
    if (msgType == 'file') {
      final file = item['file'] as Map<String, dynamic>?;
      final name = file?['fileName'] as String?;
      return name?.isNotEmpty == true ? name! : 'Файл';
    }
    if (msgType == 'link') return 'Ссылка';
    if (msgType == 'report') return 'Отчет';
    if (msgType == 'chat') return 'Чат';
  }
  final meta = item['meta'] as Map<String, dynamic>?;
  final itemText = meta?['itemText'] as String?;
  if (itemText != null && itemText.trim().isNotEmpty) return itemText.trim();
  final fallback = content?['text'] as String?;
  if (fallback != null && fallback.trim().isNotEmpty) return fallback.trim();
  return '';
}

Uint8List? _decodeImage(String? dataUri) {
  if (dataUri == null || dataUri.isEmpty) return null;
  final marker = 'base64,';
  final idx = dataUri.indexOf(marker);
  if (idx == -1) return null;
  final b64 = dataUri.substring(idx + marker.length);
  try {
    final bytes = base64Decode(b64);
    if (!_looksLikeImage(bytes)) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

bool _looksLikeImage(Uint8List bytes) {
  if (bytes.length < 4) return false;
  // JPEG
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
  // PNG
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return true;
  }
  // GIF
  if (bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return true;
  }
  // WEBP (RIFF....WEBP)
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return true;
  }
  // BMP
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) return true;
  return false;
}

/// Parsed contact info
class ContactInfo {
  const ContactInfo({
    required this.contactId,
    this.displayName = '',
    this.status = '',
  });

  final int contactId;
  final String displayName;
  final String status;

  factory ContactInfo.fromJson(Map<String, dynamic> json) {
    final contact = json['contact'] as Map<String, dynamic>? ?? {};
    return ContactInfo(
      contactId: json['contactId'] as int? ?? contact['contactId'] as int? ?? 0,
      displayName:
          contact['displayName'] as String? ??
          contact['localDisplayName'] as String? ??
          '',
      status: json['status'] as String? ?? '',
    );
  }
}

/// Parsed contact request info
class ContactRequestPreview {
  const ContactRequestPreview({
    required this.contactRequestId,
    required this.localDisplayName,
    this.displayName = '',
    this.fullName = '',
    this.shortDescr = '',
    this.contactId,
    this.userContactLinkId,
  });

  final int contactRequestId;
  final String localDisplayName;
  final String displayName;
  final String fullName;
  final String shortDescr;
  final int? contactId;
  final int? userContactLinkId;

  factory ContactRequestPreview.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>? ?? {};
    return ContactRequestPreview(
      contactRequestId: json['contactRequestId'] as int? ?? 0,
      localDisplayName: json['localDisplayName'] as String? ?? '',
      displayName:
          profile['displayName'] as String? ??
          json['localDisplayName'] as String? ??
          '',
      fullName: profile['fullName'] as String? ?? '',
      shortDescr: profile['shortDescr'] as String? ?? '',
      contactId: json['contactId_'] as int?,
      userContactLinkId: json['userContactLinkId_'] as int?,
    );
  }
}

// ===== Providers =====
final persistedProfileProvider = FutureProvider<ProfileData?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool('profile_created') ?? false)) return null;
  final raw = prefs.getString('profile_data');
  if (raw == null) return null;
  return ProfileData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
});

Future<void> saveProfileData(ProfileData d) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('profile_created', true);
  await prefs.setString('profile_data', jsonEncode(d.toJson()));
}

Future<void> clearProfileData() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('profile_created');
  await prefs.remove('profile_data');
}

Future<ProfileData?> loadProfileData() async {
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool('profile_created') ?? false)) return null;
  final raw = prefs.getString('profile_data');
  if (raw == null) return null;
  return ProfileData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
