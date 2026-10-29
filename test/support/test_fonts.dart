import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/design/app_typography.dart';

/// Loads the faces the app ships so goldens paint real text, icons and colour
/// emoji instead of the test font's tofu boxes.
Future<void> loadTestFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;

  final roboto = FontLoader('Roboto');
  for (final name in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    final file = File('${dir.path}/$name');
    if (!file.existsSync()) continue;
    roboto.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await roboto.load();

  // Without the icon font every Icon renders as a hollow square in goldens.
  final icons = File('${dir.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }

  // Snippets use the platform monospace family; the test engine has no
  // fontconfig lookup, so register a real mono face under that name.
  for (final path in [
    '/usr/share/fonts/TTF/DejaVuSansMono.ttf',
    '/usr/share/fonts/dejavu/DejaVuSansMono.ttf',
  ]) {
    final mono = File(path);
    if (!mono.existsSync()) continue;
    await (FontLoader(
          'monospace',
        )..addFont(Future.value(ByteData.sublistView(mono.readAsBytesSync()))))
        .load();
    break;
  }

  // Colour emoji are bundled with the app, so the goldens load the same face
  // the runtime uses.
  final emoji = File('assets/fonts/NotoColorEmoji.ttf');
  if (emoji.existsSync()) {
    await (FontLoader(
          emojiFontFamily,
        )..addFont(Future.value(ByteData.sublistView(emoji.readAsBytesSync()))))
        .load();
  }
}
