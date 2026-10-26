import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/chat_list_panel.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/details_panel.dart';
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
      child: MaterialApp(theme: theme.toMaterial(), home: const MessengerShell()),
    ),
  );
}

Future<FakeChatCore> _pumpShell(
  WidgetTester tester, {
  List<Map<String, dynamic>>? users,
  int? activeUserId,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final core = FakeChatCore(
    chats: demoChats(_now),
    messages: demoConversations(_now),
    now: _now,
    users: users,
    activeUserId: activeUserId,
  );
  await tester.pumpWidget(_app(core));
  await tester.pumpAndSettle();
  return core;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
}

Finder _dialogText(String text) =>
    find.descendant(of: find.byType(Dialog), matching: find.text(text));

Finder _dialogFields() =>
    find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));

void main() {
  testWidgets('menu shows profile, accounts and navigation', (tester) async {
    await _pumpShell(tester);
    await _openMenu(tester);

    expect(find.text('ACCOUNTS'), findsOneWidget);
    expect(find.text('Alex Morgan'), findsNWidgets(2));
    expect(find.text('Alex Morgan Jr.'), findsOneWidget);
    expect(find.text('Add profile'), findsOneWidget);
    expect(find.text('New chat'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Night mode'), findsOneWidget);
  });

  testWidgets('own profile opens, copies the address and edits the name', (
    tester,
  ) async {
    final core = await _pumpShell(tester);
    await _openMenu(tester);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Building TangleX'), findsOneWidget);

    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(find.textContaining('simplex:/contact'), findsOneWidget);

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);

    await tester.enterText(
      _dialogFields().first,
      'Alex Morganov',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final profile = core.users.first['profile'] as Map<String, dynamic>;
    expect(profile['displayName'], 'Alex Morganov');
    expect(find.text('Alex Morganov'), findsOneWidget);
  });

  testWidgets('adding a profile switches to it', (tester) async {
    final core = await _pumpShell(tester);
    await _openMenu(tester);

    await tester.tap(find.text('Add profile'));
    await tester.pumpAndSettle();
    expect(find.text('New profile'), findsOneWidget);

    await tester.enterText(_dialogFields().first, 'Work');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(core.users, hasLength(2));
    final created = core.users.last['profile'] as Map<String, dynamic>;
    expect(created['displayName'], 'Work');
    expect((await core.getAccounts()).activeUserId, core.users.last['userId']);
    expect(find.text('Work'), findsWidgets);

    await tester.tap(find.text('Alex Morgan'));
    await tester.pumpAndSettle();
    expect((await core.getAccounts()).activeUserId, 1);
  });

  testWidgets('new chat connects by link', (tester) async {
    final core = await _pumpShell(tester);
    await _openMenu(tester);

    await tester.tap(find.text('New chat'));
    await tester.pumpAndSettle();
    expect(_dialogText('New chat'), findsOneWidget);

    await tester.enterText(
      _dialogFields().first,
      'simplex:/contact#/?v=2-7&smp=smp7.simplex.im%2Fpeer',
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(core.connectedLinks, [
      'simplex:/contact#/?v=2-7&smp=smp7.simplex.im%2Fpeer',
    ]);
    expect(find.text('Connect'), findsNothing);
    expect(find.text('Connection request sent'), findsOneWidget);
  });

  testWidgets('new chat shows the core error and keeps the dialog open', (
    tester,
  ) async {
    final core = await _pumpShell(tester);
    core.failConnect = true;
    await _openMenu(tester);

    await tester.tap(find.text('New chat'));
    await tester.pumpAndSettle();

    await tester.enterText(_dialogFields().first, 'not-a-link');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(_dialogText('This is not a valid SimpleX link.'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(core.connectedLinks, isEmpty);
  });

  testWidgets('new chat explains that a bare short-link key is not enough', (
    tester,
  ) async {
    final core = await _pumpShell(tester);
    await _openMenu(tester);

    await tester.tap(find.text('New chat'));
    await tester.pumpAndSettle();

    await tester.enterText(
      _dialogFields().first,
      '3IRXGsKfTvKf8Ca2_7BrUe1Oimt_ZCh6TIWrVTKgY68',
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.textContaining('only the key from a short link'),
      ),
      findsOneWidget,
    );
    expect(core.connectedLinks, isEmpty);
  });

  testWidgets('new chat opens an existing contact', (tester) async {
    await _pumpShell(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(ChatListPanel),
        matching: find.byIcon(Icons.edit_outlined),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_dialogText('Maria K.'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.text('Maria K.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('contacts page lists direct chats and opens one', (tester) async {
    await _pumpShell(tester);
    await _openMenu(tester);

    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();

    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Alice Bergström'), findsOneWidget);
    expect(find.text('Meander Dev'), findsNothing);

    await tester.tap(find.text('Maria K.'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.text('Maria K.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('in-conversation search filters messages', (tester) async {
    await _pumpShell(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.byIcon(Icons.search),
      ),
    );
    await tester.pumpAndSettle();

    final searchField = find
        .descendant(
          of: find.byType(ConversationPanel),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(searchField, 'keys');
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.text('Sent you the room keys, see you at 8'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Привет! Скинул тебе доступ'),
      findsNothing,
    );

    await tester.enterText(searchField, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('details panel mutes the chat', (tester) async {
    final core = await _pumpShell(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.byIcon(Icons.info_outline),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(DetailsPanel), matching: find.text('Mute')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: find.byType(DetailsPanel), matching: find.text('Mute')),
    );
    await tester.pumpAndSettle();

    expect(core.muteChanges, [(chatRef: '@1', muted: true)]);
    expect(
      find.descendant(
        of: find.byType(DetailsPanel),
        matching: find.text('Unmute'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no profiles shows onboarding and creates the first one', (
    tester,
  ) async {
    final core = await _pumpShell(tester, users: []);
    expect(find.text('Welcome to TangleX'), findsOneWidget);
    expect(find.byType(ChatListPanel), findsNothing);

    await tester.tap(find.text('Create profile'));
    await tester.pumpAndSettle();
    await tester.enterText(_dialogFields().first, 'Solo');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(core.users, hasLength(1));
    expect(find.text('Welcome to TangleX'), findsNothing);
    expect(find.byType(ChatListPanel), findsOneWidget);
  });

  testWidgets('night mode updates the theme setting', (tester) async {
    await _pumpShell(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MessengerShell)),
    );
    expect(container.read(appThemeProvider).mode, ThemeMode.system);

    await _openMenu(tester);
    await tester.tap(find.text('Night mode'));
    await tester.pumpAndSettle();
    expect(container.read(appThemeProvider).mode, ThemeMode.dark);

    await tester.tap(find.text('Night mode'));
    await tester.pumpAndSettle();
    expect(container.read(appThemeProvider).mode, ThemeMode.light);
  });
}
