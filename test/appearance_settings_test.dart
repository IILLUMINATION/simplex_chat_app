import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tanglex_chat/main_design.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/shell/appearance_settings.dart';

import 'support/fake_chat_core.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('palette button opens appearance and applies a preset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final now = DateTime(2026, 10, 26, 15, 0);
    final core = FakeChatCore(
      chats: demoChats(now),
      messages: demoConversations(now),
      now: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatCoreProvider.overrideWithValue(core),
          clockProvider.overrideWithValue(() => now),
        ],
        child: const DesignPreviewApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.text('Midnight'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(AppearanceScreen));
    expect(context.appTheme.palette.windowBg, const Color(0xFF000000));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_settings_v1'), contains('amoled'));

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(
      tester.element(find.byType(AppearanceScreen)).appTheme.palette.windowBg,
      isNot(const Color(0xFF000000)),
    );
  });
}
