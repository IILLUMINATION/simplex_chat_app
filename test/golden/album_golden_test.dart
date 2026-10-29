
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/models.dart';

import '../support/test_fonts.dart';

late Uint8List _landscape;
late Uint8List _portrait;
late Uint8List _square;

/// A soft two-colour gradient so the tiles are easy to tell apart in the PNG.
Uint8List _photo(int width, int height, int seed) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final t = (x / width + y / height) / 2;
      image.setPixelRgb(
        x,
        y,
        (60 + seed * 20 + 150 * t).round(),
        (110 + seed * 15 + 90 * (1 - t)).round(),
        (150 + 60 * t).round(),
      );
    }
  }
  return img.encodeJpg(image, quality: 80);
}

AppTheme _theme(Brightness brightness) =>
    buildAppTheme(const AppThemeSettings(fontFamily: 'Roboto'), brightness);

final _now = DateTime(2026, 10, 29, 12, 0);

MessageItem _album({
  required List<Uint8List> photos,
  required bool outgoing,
  String caption = '',
}) {
  return MessageItem(
    text: caption,
    time: '12:04',
    timestamp: _now,
    outgoing: outgoing,
    sender: outgoing ? null : 'Alice',
    mediaLabel: 'Photo',
    imageBytes: photos.last,
    itemId: 20,
    album: [
      for (var i = 0; i < photos.length; i++)
        AlbumTile(bytes: photos[i], itemId: i + 1),
    ],
  );
}

Widget _harness(Brightness brightness) {
  final theme = _theme(brightness);
  return AppThemeScope(
    theme: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.toMaterial(),
      home: Scaffold(
        body: ConversationPanel(
          chat: const ChatSummary(
            id: '@1',
            name: 'Alice',
            preview: 'Photos',
            time: '12:04',
          ),
          messages: [
            MessageItem(
              text: 'Today',
              time: '',
              isDateSeparator: true,
            ),
            _album(
              photos: [_portrait, _square, _landscape],
              outgoing: true,
              caption: 'Autumn walk',
            ),
            _album(photos: [_square, _square], outgoing: false),
          ],
        ),
      ),
    ),
  );
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settleImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadTestFonts();
    _landscape = _photo(900, 600, 1);
    _portrait = _photo(600, 900, 2);
    _square = _photo(800, 800, 3);
  });

  testWidgets('desktop album mosaic light', (tester) async {
    await _setSize(tester, const Size(900, 1000));
    await tester.pumpWidget(_harness(Brightness.light));
    await tester.pumpAndSettle();
    await _settleImages(tester);
    await expectLater(
      find.byType(ConversationPanel),
      matchesGoldenFile('goldens/album_desktop_light.png'),
    );
  });

  testWidgets('phone album mosaic dark', (tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(_harness(Brightness.dark));
    await tester.pumpAndSettle();
    await _settleImages(tester);
    await expectLater(
      find.byType(ConversationPanel),
      matchesGoldenFile('goldens/album_phone_dark.png'),
    );
  });
}
