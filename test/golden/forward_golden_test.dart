import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/providers/persistent_store.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/messenger_shell.dart';

import '../support/fake_chat_core.dart';
import '../support/test_fonts.dart';

final _now = DateTime(2026, 10, 26, 15, 0);

Widget _harness(Brightness brightness) {
  final theme = buildAppTheme(
    const AppThemeSettings(fontFamily: 'Roboto'),
    brightness,
  );
  final core = FakeChatCore(
    chats: demoChats(_now),
    messages: demoConversations(_now),
    now: _now,
  );
  return ProviderScope(
    overrides: [
      chatCoreProvider.overrideWithValue(core),
      clockProvider.overrideWithValue(() => _now),
    ],
    child: AppThemeScope(
      theme: theme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.toMaterial(),
        home: const MessengerShell(),
      ),
    ),
  );
}

Widget _singleChatHarness(Brightness brightness, List<dynamic> items) {
  final theme = buildAppTheme(
    const AppThemeSettings(fontFamily: 'Roboto'),
    brightness,
  );
  final core = FakeChatCore(
    chats: [
      ChatPreview(
        chatRef: '@1',
        chatType: 'contact',
        displayName: 'Dan',
        timestamp: _now.microsecondsSinceEpoch,
        connStatusType: 'ready',
      ),
    ],
    messages: {'@1': items.cast<Map<String, dynamic>>()},
    now: _now,
  );
  return ProviderScope(
    overrides: [
      chatCoreProvider.overrideWithValue(core),
      clockProvider.overrideWithValue(() => _now),
    ],
    child: AppThemeScope(
      theme: theme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.toMaterial(),
        home: const MessengerShell(),
      ),
    ),
  );
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('forwarded bubble desktop light', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _singleChatHarness(Brightness.light, [
        textItem(
          text: 'Отлично, тогда вечером катим в ветку.',
          time: _now.subtract(const Duration(minutes: 4)),
          forwarded: true,
          forwardedFrom: 'Alice Bergström',
        ),
        textItem(
          text: 'Принял. Сначала дизайн-система, потом фичи.',
          time: _now.subtract(const Duration(minutes: 2)),
          fromMe: true,
          forwarded: true,
          forwardedFrom: 'Meander Dev',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('forwarded-label')), findsNWidgets(2));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_forwarded_bubble_light.png'),
    );
  });

  testWidgets('forward to picker desktop light', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(Brightness.light));
    await tester.pumpAndSettle();

    await tester.tap(
      find.text('Sent you the room keys, see you at 8').last,
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forward'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('forward-dialog')), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_forward_picker_light.png'),
    );
  });
}
