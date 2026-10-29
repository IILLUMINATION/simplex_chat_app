import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/design/app_typography.dart';

Future<void> _loadEmojiFont() async {
  final file = File('assets/fonts/NotoColorEmoji.ttf');
  expect(file.existsSync(), isTrue, reason: 'bundled emoji font is missing');
  await (FontLoader(emojiFontFamily)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync()))))
      .load();
  final roboto = FontLoader(defaultTextFontFamily);
  for (final name in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    final f = File('assets/fonts/$name');
    expect(f.existsSync(), isTrue, reason: 'bundled $name is missing');
    roboto.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await roboto.load();
}

/// Coloured pixels only come from the emoji bitmap strike: the test font
/// paints missing glyphs as a hollow monochrome box.
Future<int> _coloredPixels(WidgetTester tester, Widget child) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(key: key, child: ColoredBox(color: Colors.white, child: child)),
  );
  await tester.pumpAndSettle();
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final data = (await tester.runAsync(() async {
    final image = await boundary.toImage();
    return image.toByteData(format: ui.ImageByteFormat.rawRgba);
  }))!;
  var count = 0;
  for (var i = 0; i < data.lengthInBytes; i += 4) {
    final r = data.getUint8(i);
    final g = data.getUint8(i + 1);
    final b = data.getUint8(i + 2);
    final a = data.getUint8(i + 3);
    final max = [r, g, b].reduce((x, y) => x > y ? x : y);
    final min = [r, g, b].reduce((x, y) => x < y ? x : y);
    if (a > 200 && max - min > 60) count++;
  }
  return count;
}

void main() {
  setUpAll(_loadEmojiFont);

  testWidgets('material theme carries the bundled emoji fallback', (tester) async {
    final theme = buildAppTheme(const AppThemeSettings(), Brightness.light);
    final text = theme.toMaterial().textTheme;
    // bodyMedium/bodySmall come from AppTypography; displaySmall is only
    // touched by ThemeData's own fontFamilyFallback.
    for (final style in [
      text.bodyMedium!,
      text.bodySmall!,
      text.displaySmall!,
    ]) {
      expect(style.fontFamilyFallback, contains(emojiFontFamily));
    }
    expect(theme.typography.message.fontFamilyFallback, contains(emojiFontFamily));
    expect(theme.typography.messageMeta.fontFamilyFallback, contains(emojiFontFamily));
  });

  // The bundled pack is the sbix build of Noto Color Emoji and ships no
  // regional indicators, so flags and any glyph newer than the pack must be
  // served by the platform emoji font. That only works while the bundled
  // family is app-specific and the system families follow it.
  testWidgets('pack gaps fall through to the platform emoji font', (tester) async {
    expect(emojiFontFallback, [
      emojiFontFamily,
      'Apple Color Emoji',
      'Segoe UI Emoji',
      'Noto Color Emoji',
      'sans-serif',
    ]);
    expect(emojiFontFamily, isNot('Noto Color Emoji'));
    final text = buildAppTheme(
      const AppThemeSettings(),
      Brightness.light,
    ).toMaterial().textTheme;
    for (final style in [text.bodyMedium!, text.displaySmall!]) {
      expect(style.fontFamilyFallback!.first, emojiFontFamily);
      expect(style.fontFamilyFallback, contains('Noto Color Emoji'));
    }
  });

  testWidgets('text styles pin a real family before the emoji fallback', (tester) async {
    final t = buildAppTheme(const AppThemeSettings(), Brightness.light).typography;
    for (final style in [
      t.message,
      t.messageMeta,
      t.listTime,
      t.listName,
      t.badge,
      t.input,
    ]) {
      // A null family makes Skia take digits from the colour emoji keycap
      // glyphs, which is what turned timestamps into hollow, wide digits.
      expect(style.fontFamily, isNotNull);
      expect(style.fontFamily, isNot(emojiFontFamily));
    }
  });

  // Reproduces the picker bug on machines where DejaVu is present: a primary
  // face that covers 😀 and ❤ as outlines wins before the emoji fallback, so
  // those glyphs paint monochrome. The app's Roboto primary must not do that.
  testWidgets('a primary face with monochrome emoji loses to the pack', (tester) async {
    final dejavu = File('/usr/share/fonts/TTF/DejaVuSans.ttf');
    if (!dejavu.existsSync()) return; // no DejaVu on this machine
    await (FontLoader(
      'DejaVu Sans',
    )..addFont(Future.value(ByteData.sublistView(dejavu.readAsBytesSync())))).load();

    Future<int> coloured(TextStyle style) => _coloredPixels(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(const AppThemeSettings(), Brightness.light).toMaterial(),
        home: Material(
          child: Center(child: Text('😀❤', style: style.copyWith(fontSize: 64))),
        ),
      ),
    );

    const dejavuStyle = TextStyle(
      fontFamily: 'DejaVu Sans',
      fontFamilyFallback: emojiFontFallback,
    );
    expect(await coloured(dejavuStyle), 0);

    final appStyle = buildAppTheme(
      const AppThemeSettings(),
      Brightness.light,
    ).typography.message;
    expect(await coloured(appStyle), greaterThan(1000));
  });

  testWidgets('inherited theme text paints emoji in colour', (tester) async {
    final theme = buildAppTheme(const AppThemeSettings(), Brightness.light);
    final count = await _coloredPixels(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.toMaterial(),
        home: const Material(
          child: Center(child: Text('😀', style: TextStyle(fontSize: 64))),
        ),
      ),
    );
    expect(count, greaterThan(500));
  });

  // Negative control: without the fallback the glyph is a tofu box, i.e. the
  // same harness reports no coloured pixels.
  testWidgets('dropping the emoji fallback paints no colour', (tester) async {
    final theme = buildAppTheme(const AppThemeSettings(), Brightness.light);
    final count = await _coloredPixels(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.toMaterial(),
        home: const Material(
          child: Center(
            child: Text(
              '😀',
              style: TextStyle(fontSize: 64, fontFamilyFallback: []),
            ),
          ),
        ),
      ),
    );
    expect(count, 0);
  });
}
