import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/appearance_settings.dart';
import 'package:tanglex_chat/src/shell/messenger_shell.dart';
import 'package:tanglex_chat/src/shell/window_chrome.dart';

import '../support/fake_chat_core.dart';
import '../support/test_fonts.dart';

AppTheme _theme(Brightness brightness) =>
    buildAppTheme(const AppThemeSettings(fontFamily: 'Roboto'), brightness);

final _now = DateTime(2026, 10, 26, 15, 0);

Widget _harness(AppTheme theme) {
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

Widget _appearanceHarness(AppThemeSettings settings, Brightness brightness) {
  final themed = settings.copyWith(fontFamily: 'Roboto');
  final theme = buildAppTheme(themed, brightness);
  return AppThemeScope(
    theme: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.toMaterial(),
      home: AppearanceScreen(settings: themed, onChanged: (_) {}),
    ),
  );
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Photo bubbles paint through an async codec, which `pumpAndSettle` alone
/// never resolves — without this every golden shows the empty bubble colour.
Future<void> _settleImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('desktop two-column light', (tester) async {
    await _setSize(tester, const Size(1280, 800));
    await tester.pumpWidget(_harness(_theme(Brightness.light)));
    await tester.pumpAndSettle();

    await _settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_light.png'),
    );
  });

  testWidgets('desktop three-column dark', (tester) async {
    await _setSize(tester, const Size(1440, 900));
    await tester.pumpWidget(_harness(_theme(Brightness.dark)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('conversation-header')));
    await tester.pumpAndSettle();

    await _settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_dark_details.png'),
    );
  });

  testWidgets('desktop compact chat list light', (tester) async {
    await _setSize(tester, const Size(1280, 800));
    await tester.pumpWidget(_harness(_theme(Brightness.light)));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('chat-list-resize')),
      const Offset(-400, 0),
      touchSlopX: 0,
    );
    await tester.pumpAndSettle();

    await _settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_compact_light.png'),
    );
  });

  testWidgets('desktop message actions light', (tester) async {
    await _setSize(tester, const Size(1280, 800));
    await tester.pumpWidget(_harness(_theme(Brightness.light)));
    await tester.pumpAndSettle();

    await tester.tap(
      find.text('Sent you the room keys, see you at 8').last,
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    await _settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_actions_light.png'),
    );
  });

  testWidgets('phone chat list light', (tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(_harness(_theme(Brightness.light)));
    await tester.pumpAndSettle();

    await _settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_light.png'),
    );
  });

  testWidgets('desktop photo bubble with an upload ring', (tester) async {
    await _setSize(tester, const Size(1280, 800));
    final core = FakeChatCore(
      chats: demoChats(_now),
      messages: {
        '@1': [
          imageItem(
            time: _now.add(const Duration(seconds: 1)),
            fileName: 'photo.jpg',
            size: 412000,
            fromMe: true,
            fileId: 11,
            fileStatus: 'sndTransfer',
            progress: 120000,
            total: 412000,
          ),
        ],
      },
      now: _now,
    );
    final theme = _theme(Brightness.light);
    await tester.pumpWidget(
      ProviderScope(
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
      ),
    );
    await tester.pumpAndSettle();

    await _settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_upload_light.png'),
    );
  });

  testWidgets('phone conversation dark', (tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(_harness(_theme(Brightness.dark)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice Bergström'));
    await tester.pumpAndSettle();

    await _settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_dark_chat.png'),
    );
  });

  testWidgets(
    'window title strip matches the Telegram frame',
    (tester) async {
      await _setSize(tester, const Size(320, 60));
      final theme = _theme(Brightness.dark);
      await tester.pumpWidget(
        AppThemeScope(
          theme: theme,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.toMaterial(),
            home: const WindowChrome(
              child: ColoredBox(color: Color(0xFF17212B)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _settleImages(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/title_strip_dark.png'),
      );
    },
    skip: !WindowChrome.supported,
  );

  testWidgets(
    'window title strip shows the restore glyph when maximized',
    (tester) async {
      await _setSize(tester, const Size(320, 60));
      WindowChromeController.instance.maximized.value = true;
      addTearDown(
        () => WindowChromeController.instance.maximized.value = false,
      );
      final theme = _theme(Brightness.dark);
      await tester.pumpWidget(
        AppThemeScope(
          theme: theme,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.toMaterial(),
            home: const WindowChrome(
              child: ColoredBox(color: Color(0xFF17212B)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _settleImages(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/title_strip_dark_maximized.png'),
      );
    },
    skip: !WindowChrome.supported,
  );

  testWidgets('appearance desktop light', (tester) async {
    await _setSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      _appearanceHarness(const AppThemeSettings(), Brightness.light),
    );
    await tester.pumpAndSettle();

    await _settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/appearance_desktop_light.png'),
    );
  });

  testWidgets('appearance phone dark', (tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(
      _appearanceHarness(
        const AppThemeSettings(mode: ThemeMode.dark),
        Brightness.dark,
      ),
    );
    await tester.pumpAndSettle();

    await _settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/appearance_phone_dark.png'),
    );
  });

  testWidgets('main menu desktop light', (tester) async {
    await _setSize(tester, const Size(1280, 800));
    await tester.pumpWidget(_harness(_theme(Brightness.light)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    await _settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/menu_desktop_light.png'),
    );
  });

  testWidgets('main menu phone dark', (tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(_harness(_theme(Brightness.dark)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    await _settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/menu_phone_dark.png'),
    );
  });

  testWidgets('own profile desktop light', (tester) async {
    await _setSize(tester, const Size(1280, 800));
    await tester.pumpWidget(_harness(_theme(Brightness.light)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    await _settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/profile_desktop_light.png'),
    );
  });
}
