import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Files and images the OS clipboard holds for a chat paste.
///
/// Paths point at real files: Linux hands over the local URI targets and
/// writes a raw bitmap to a temp PNG, Android copies `content://` streams
/// into the app cache first.
class ClipboardPayload {
  const ClipboardPayload({this.paths = const []});

  final List<String> paths;

  bool get isEmpty => paths.isEmpty;
}

/// Reads clipboard files through the native side (`tanglex/clipboard`).
///
/// Telegram asks the mime data for local files first and only falls back to
/// the plain-text/rich paste afterwards (`HistoryWidget::canSendFiles`,
/// `confirmSendingFiles` in `history_widget.cpp`); the composer follows the
/// same order when the shortcut or the Paste menu item fires.
class ClipboardFiles {
  static const _channel = MethodChannel('tanglex/clipboard');

  static Future<ClipboardPayload> read() async {
    if (kIsWeb) return const ClipboardPayload();
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'readFiles',
      );
      if (result == null) return const ClipboardPayload();
      final paths = <String>[];
      final rawPaths = result['paths'];
      if (rawPaths is List) {
        for (final path in rawPaths) {
          if (path is String && path.isNotEmpty && File(path).existsSync()) {
            paths.add(path);
          }
        }
      }
      final imagePath = result['imagePath'];
      if (paths.isEmpty &&
          imagePath is String &&
          imagePath.isNotEmpty &&
          File(imagePath).existsSync()) {
        paths.add(imagePath);
      }
      return ClipboardPayload(paths: paths);
    } on MissingPluginException {
      return const ClipboardPayload();
    } on PlatformException {
      return const ClipboardPayload();
    }
  }
}
