import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/providers/persistent_store.dart';
import 'package:tanglex_chat/src/shell/messenger_shell.dart';

import '../support/fake_chat_core.dart';
import '../support/test_fonts.dart';

AppTheme _theme(Brightness brightness) =>
    buildAppTheme(const AppThemeSettings(fontFamily: 'Roboto'), brightness);

final _now = DateTime(2026, 10, 29, 15, 0);

const _outgoingText = 'Sent you the room keys, see you at 8';

Widget _harness(AppTheme theme) {
  final core = FakeChatCore(
    chats: [
      ChatPreview(
        chatRef: '@1',
        chatType: 'contact',
        displayName: 'Alice Bergström',
        timestamp: _now.microsecondsSinceEpoch,
        connStatusType: 'ready',
        fullName: 'Alice Bergström',
      ),
    ],
    messages: {
      '@1': [
        textItem(
          text: 'Отлично, тогда вечером катим в ветку.',
          time: _now.subtract(const Duration(minutes: 10)),
        ),
        textItem(
          text: 'Принял. Сначала дизайн-система, потом фичи.',
          time: _now.subtract(const Duration(minutes: 8)),
          fromMe: true,
          edited: true,
          editable: true,
          deletable: true,
        ),
        textItem(
          text: _outgoingText,
          time: _now.subtract(const Duration(minutes: 6)),
          fromMe: true,
          editable: true,
          deletable: true,
        ),
      ],
    },
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

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _openMenu(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('actions menu offers Edit on an editable message', (
    tester,
  ) async {
    await _setSize(tester, const Size(1280, 800));
    await tester.pumpWidget(_harness(_theme(Brightness.light)));
    await tester.pumpAndSettle();
    await _openMenu(tester, _outgoingText);

    expect(find.text('Edit'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_actions_editable_light.png'),
    );
  });

  testWidgets('edit mode mirrors Telegram composer', (tester) async {
    await _setSize(tester, const Size(1280, 800));
    await tester.pumpWidget(_harness(_theme(Brightness.light)));
    await tester.pumpAndSettle();
    await _openMenu(tester, _outgoingText);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('edit-bar')), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_edit_mode_light.png'),
    );
  });

  testWidgets('delete dialog light', (tester) async {
    await _setSize(tester, const Size(1280, 800));
    await tester.pumpWidget(_harness(_theme(Brightness.light)));
    await tester.pumpAndSettle();
    await _openMenu(tester, _outgoingText);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('delete-dialog')), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_delete_dialog_light.png'),
    );
  });
}
