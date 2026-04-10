import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Локально закреплённое сообщение
class PinnedMessage {
  final String chatRef; // ID чата
  final String key; // уникальный ключ сообщения
  final String text;
  final String? imageFilePath;
  final String timeStr;
  final DateTime pinnedAt;

  const PinnedMessage({
    required this.chatRef,
    required this.key,
    required this.text,
    this.imageFilePath,
    required this.timeStr,
    required this.pinnedAt,
  });

  Map<String, dynamic> toJson() => {
        'chatRef': chatRef,
        'key': key,
        'text': text,
        'imageFilePath': imageFilePath,
        'timeStr': timeStr,
        'pinnedAt': pinnedAt.toIso8601String(),
      };

  static PinnedMessage fromJson(Map<String, dynamic> json) {
    return PinnedMessage(
      chatRef: json['chatRef'] as String,
      key: json['key'] as String,
      text: json['text'] as String,
      imageFilePath: json['imageFilePath'] as String?,
      timeStr: json['timeStr'] as String,
      pinnedAt: DateTime.parse(json['pinnedAt'] as String),
    );
  }
}

/// Локальное хранилище закреплённых сообщений (по чатам, множественные)
class PinStore {
  PinStore._();
  static final PinStore instance = PinStore._();

  // chatRef -> список закреплённых сообщений
  final Map<String, List<PinnedMessage>> _pinned = {};

  List<PinnedMessage> getPinned(String chatRef) {
    return List.unmodifiable(_pinned[chatRef] ?? []);
  }

  int getPinCount(String chatRef) => (_pinned[chatRef] ?? []).length;

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/pin_store');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<File> _file() async {
    final d = await _dir();
    return File('${d.path}/pinned.json');
  }

  Future<void> load() async {
    final f = await _file();
    if (!f.existsSync()) return;
    try {
      final raw = jsonDecode(f.readAsStringSync()) as List;
      _pinned.clear();
      for (final e in raw.whereType<Map>()) {
        final pm = PinnedMessage.fromJson(Map<String, dynamic>.from(e));
        _pinned.putIfAbsent(pm.chatRef, () => []);
        _pinned[pm.chatRef]!.add(pm);
      }
    } catch (_) {}
  }

  Future<void> save() async {
    final f = await _file();
    final data = _pinned.values.expand((v) => v).map((p) => p.toJson()).toList();
    f.writeAsStringSync(jsonEncode(data));
  }

  bool isPinned(String chatRef, String key) {
    return (_pinned[chatRef] ?? []).any((p) => p.key == key);
  }

  Future<void> pin(PinnedMessage msg) async {
    _pinned.putIfAbsent(msg.chatRef, () => []);
    // Не добавляем дубликаты
    final list = _pinned[msg.chatRef]!;
    if (!list.any((p) => p.key == msg.key)) {
      list.add(msg);
    }
    await save();
  }

  Future<void> unpin(String chatRef, String key) async {
    _pinned[chatRef]?.removeWhere((p) => p.key == key);
    if (_pinned[chatRef]?.isEmpty ?? false) {
      _pinned.remove(chatRef);
    }
    await save();
  }

  /// Заменить все закрепы чата (для массовой операции)
  Future<void> replacePins(String chatRef, List<PinnedMessage> pins) async {
    _pinned[chatRef] = List.from(pins);
    await save();
  }
}
