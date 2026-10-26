import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/chat_list_panel.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/messenger_shell.dart';

import 'support/fake_chat_core.dart';

final _now = DateTime(2026, 10, 26, 15, 0);

Widget _app(FakeChatCore core) {
  final theme = buildAppTheme(
    const AppThemeSettings(fontFamily: 'Roboto'),
    Brightness.light,
  );
  return ProviderScope(
    overrides: [
      chatCoreProvider.overrideWithValue(core),
      clockProvider.overrideWithValue(() => _now),
    ],
    child: AppThemeScope(
      theme: theme,
      child: MaterialApp(home: const MessengerShell()),
    ),
  );
}

Future<FakeChatCore> _pumpShell(
  WidgetTester tester, {
  bool failSend = false,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final core = FakeChatCore(
    chats: demoChats(_now),
    messages: demoConversations(_now),
    now: _now,
  )..failSend = failSend;
  await tester.pumpWidget(_app(core));
  await tester.pumpAndSettle();
  return core;
}

Finder _composer() => find.descendant(
  of: find.byType(ConversationPanel),
  matching: find.byType(TextField),
);

void main() {
  testWidgets('chat list comes from the core', (tester) async {
    await _pumpShell(tester);

    final list = find.byType(ChatListPanel);
    expect(
      find.descendant(of: list, matching: find.text('Alice Bergström')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: list, matching: find.text('Meander Dev')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: list,
        matching: find.text('Sent you the room keys, see you at 8'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('opening a chat loads its history', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.text('Meander Dev'));
    await tester.pumpAndSettle();

    final list = tester.widget<ConversationPanel>(
      find.byType(ConversationPanel),
    );
    expect(list.chat.name, 'Meander Dev');
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('the first chat is selected on desktop and marked read', (
    tester,
  ) async {
    final core = await _pumpShell(tester);

    expect(find.byType(ConversationPanel), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.text('Sent you the room keys, see you at 8'),
      ),
      findsOneWidget,
    );
    expect(core.readChats, contains('@1'));
  });

  testWidgets('send button delivers the typed text to the core', (
    tester,
  ) async {
    final core = await _pumpShell(tester);

    await tester.enterText(_composer(), 'ping from the shell');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(core.sentTexts, ['ping from the shell']);
    // The optimistic bubble is reconciled with the core copy.
    expect(find.text('ping from the shell'), findsOneWidget);
  });

  testWidgets('Enter sends without Shift', (tester) async {
    final core = await _pumpShell(tester);

    await tester.enterText(_composer(), 'via enter');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(core.sentTexts, ['via enter']);
  });

  testWidgets('Shift+Enter inserts a newline instead of sending', (
    tester,
  ) async {
    final core = await _pumpShell(tester);

    await tester.enterText(_composer(), 'line one');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(core.sentTexts, isEmpty);
  });

  testWidgets('an empty composer does not send anything', (tester) async {
    final core = await _pumpShell(tester);

    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(core.sentTexts, isEmpty);
  });

  testWidgets('a rejected send leaves the bubble in the failed state', (
    tester,
  ) async {
    await _pumpShell(tester, failSend: true);

    await tester.enterText(_composer(), 'this will fail');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
