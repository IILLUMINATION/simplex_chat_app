import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/models.dart';

import '../support/test_fonts.dart';

const _clipboard = MethodChannel('tanglex/clipboard');

Uint8List _pngBytes() {
  final image = img.Image(width: 96, height: 96);
  img.fill(image, color: img.ColorRgb8(78, 118, 168));
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if ((x + y) % 48 < 4) {
        img.drawPixel(image, x, y, img.ColorRgb8(196, 214, 236));
      }
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

AppTheme _theme(Brightness brightness) =>
    buildAppTheme(const AppThemeSettings(fontFamily: 'Roboto'), brightness);

Future<void> _settleImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> pumpWithPasted(
    WidgetTester tester, {
    required Brightness brightness,
    required Size size,
  }) async {
    await loadTestFonts();
    final dir = Directory.systemTemp.createTempSync('tanglex-paste-golden');
    addTearDown(() => dir.deleteSync(recursive: true));
    final photo = File('${dir.path}/sunset.png')
      ..writeAsBytesSync(_pngBytes());
    final report = File('${dir.path}/quarterly-report.pdf')
      ..writeAsBytesSync(List<int>.filled(4096, 5));
    messenger.setMockMethodCallHandler(_clipboard, (call) async {
      if (call.method != 'readFiles') return null;
      return {
        'paths': [photo.path, report.path],
        'imagePath': null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_clipboard, null));

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = _theme(brightness);
    await tester.pumpWidget(
      AppThemeScope(
        theme: theme,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.toMaterial(),
          home: Scaffold(
            body: ConversationPanel(
              chat: const ChatSummary(
                id: '@1',
                name: 'Alice',
                preview: 'Pasted',
                time: '12:04',
              ),
              messages: const [
                MessageItem(
                  text: 'Photos from the trip?',
                  time: '12:03',
                  sender: 'Alice',
                  outgoing: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await _settleImages(tester);
  }

  testWidgets('composer paste preview, desktop light', (tester) async {
    await pumpWithPasted(
      tester,
      brightness: Brightness.light,
      size: const Size(900, 700),
    );

    await expectLater(
      find.byType(ConversationPanel),
      matchesGoldenFile('goldens/clipboard_paste_desktop_light.png'),
    );
  });

  testWidgets('composer paste preview, phone dark', (tester) async {
    await pumpWithPasted(
      tester,
      brightness: Brightness.dark,
      size: const Size(390, 844),
    );

    await expectLater(
      find.byType(ConversationPanel),
      matchesGoldenFile('goldens/clipboard_paste_phone_dark.png'),
    );
  });
}
