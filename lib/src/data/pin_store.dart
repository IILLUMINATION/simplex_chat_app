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

  /// Сериализует все мутации (pin/unpin/save) чтобы:
  ///  1) не было гонок (последовательный last-write-wins → потеря данных),
  ///  2) load() гарантированно завершился до первой записи.
  Future<void> _writeChain = Future<void>.value();
  bool _loaded = false;
  Future<void>? _loadFuture;

  List<PinnedMessage> getPinned(String chatRef) {
    return List.unmodifiable(_pinned[chatRef] ?? []);
  }

  int getPinCount(String chatRef) => (_pinned[chatRef] ?? []).length;

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/pin_store');
    // FIX: sync IO в UI потоке. Используем async-варианты.
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  Future<File> _file() async {
    final d = await _dir();
    return File('${d.path}/pinned.json');
  }

  Future<void> load() {
    // Гарантируем, что load выполнится ровно один раз и последующие await
    // вернут тот же Future, не запуская повторное чтение.
    return _loadFuture ??= _doLoad();
  }

  Future<void> _doLoad() async {
    try {
      final f = await _file();
      if (!await f.exists()) {
        _loaded = true;
        return;
      }
      final content = await f.readAsString();
      final raw = jsonDecode(content) as List;
      _pinned.clear();
      for (final e in raw.whereType<Map>()) {
        final pm = PinnedMessage.fromJson(Map<String, dynamic>.from(e));
        _pinned.putIfAbsent(pm.chatRef, () => []);
        _pinned[pm.chatRef]!.add(pm);
      }
    } catch (_) {
      // Тихо игнорируем — повреждённый файл не должен валить UI.
    } finally {
      _loaded = true;
    }
  }

  Future<void> _save() async {
    final f = await _file();
    final data =
        _pinned.values.expand((v) => v).map((p) => p.toJson()).toList();
    await f.writeAsString(jsonEncode(data));
  }

  /// Внешний save — упорядочивается через цепочку чтобы избежать гонок.
  Future<void> save() => _enqueue(_save);

  Future<void> _enqueue(Future<void> Function() op) {
    // Сначала дожидаемся load (если ещё не загрузились).
    final ensureLoaded = _loaded ? Future<void>.value() : load();
    final next = _writeChain.then((_) => ensureLoaded).then((_) => op());
    // Не пробрасываем ошибки в цепочку — иначе одна неудачная запись
    // заблокирует все последующие.
    _writeChain = next.catchError((_) {});
    return next;
  }

  bool isPinned(String chatRef, String key) {
    return (_pinned[chatRef] ?? []).any((p) => p.key == key);
  }

  Future<void> pin(PinnedMessage msg) {
    return _enqueue(() async {
      _pinned.putIfAbsent(msg.chatRef, () => []);
      final list = _pinned[msg.chatRef]!;
      if (!list.any((p) => p.key == msg.key)) {
        list.add(msg);
      }
      await _save();
    });
  }

  Future<void> unpin(String chatRef, String key) {
    return _enqueue(() async {
      _pinned[chatRef]?.removeWhere((p) => p.key == key);
      if (_pinned[chatRef]?.isEmpty ?? false) {
        _pinned.remove(chatRef);
      }
      await _save();
    });
  }

  /// Заменить все закрепы чата (для массовой операции)
  Future<void> replacePins(String chatRef, List<PinnedMessage> pins) {
    return _enqueue(() async {
      _pinned[chatRef] = List.from(pins);
      await _save();
    });
  }
}
