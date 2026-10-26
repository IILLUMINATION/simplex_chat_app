import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/appearance_settings.dart';
import 'package:tanglex_chat/src/shell/messenger_shell.dart';

import '../support/fake_chat_core.dart';

Future<void> _loadFonts() async {
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
}

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

void main() {
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('desktop two-column light', (tester) async {
    await _setSize(tester, const Size(1280, 800));
    await tester.pumpWidget(_harness(_theme(Brightness.light)));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_light.png'),
    );
  });

  testWidgets('desktop three-column dark', (tester) async {
    await _setSize(tester, const Size(1440, 900));
    await tester.pumpWidget(_harness(_theme(Brightness.dark)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_dark_details.png'),
    );
  });

  testWidgets('phone chat list light', (tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(_harness(_theme(Brightness.light)));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_light.png'),
    );
  });

  testWidgets('phone conversation dark', (tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(_harness(_theme(Brightness.dark)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice Bergström'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_dark_chat.png'),
    );
  });

  testWidgets('appearance desktop light', (tester) async {
    await _setSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      _appearanceHarness(const AppThemeSettings(), Brightness.light),
    );
    await tester.pumpAndSettle();

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

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/profile_desktop_light.png'),
    );
  });
}
