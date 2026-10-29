import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/providers/persistent_store.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/service/tanglex_service.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/messenger_shell.dart';

import 'support/fake_chat_core.dart';

final _now = DateTime(2026, 10, 29, 9, 30);

final _theme = buildAppTheme(
  const AppThemeSettings(fontFamily: 'Roboto'),
  Brightness.light,
);

/// Records the command strings the UI would hand to the core and replies with
/// a canned API response, so the wire format can be asserted without FFI.
class _RecordingService extends TanglexService {
  _RecordingService(this.reply);

  final String reply;
  final List<String> commands = [];

  @override
  Future<String?> sendCommand(String cmd) async {
    commands.add(cmd);
    return reply;
  }
}

ChatPreview _directChat() => ChatPreview(
  chatRef: '@1',
  chatType: 'contact',
  displayName: 'Alice',
  timestamp: _now.microsecondsSinceEpoch,
  connStatusType: 'ready',
  contactStatus: 'active',
);

Future<FakeChatCore> _pumpShell(
  WidgetTester tester, {
  required List<Map<String, dynamic>> items,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final core = FakeChatCore(
    chats: [_directChat()],
    messages: {'@1': items},
    now: _now,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatCoreProvider.overrideWithValue(core),
        clockProvider.overrideWithValue(() => _now),
      ],
      child: AppThemeScope(
        theme: _theme,
        child: MaterialApp(home: const MessengerShell()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return core;
}

Finder _composer() => find.descendant(
  of: find.byType(ConversationPanel),
  matching: find.byType(TextField),
);

Future<void> _openMenu(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  group('core commands', () {
    test('edit uses the documented /_update item grammar', () async {
      final service = _RecordingService(
        '{"result":{"type":"chatItemUpdated"}}',
      );
      expect(await service.editMessage('@1', 42, 'hello world'), isTrue);
      expect(service.commands, ['/_update item @1 42 text hello world']);
    });

    test('edit keeps newlines escaped like /_send', () async {
      final service = _RecordingService(
        '{"result":{"type":"chatItemUpdated"}}',
      );
      await service.editMessage('@1', 42, 'one\ntwo');
      expect(service.commands, ['/_update item @1 42 text one\\ntwo']);
    });

    test('an unchanged edit is still a success', () async {
      final service = _RecordingService(
        '{"result":{"type":"chatItemNotChanged"}}',
      );
      expect(await service.editMessage('@1', 42, 'same'), isTrue);
    });

    test('edit reports core errors', () async {
      final service = _RecordingService(
        '{"result":{"type":"chatCmdError"}}',
      );
      expect(await service.editMessage('@1', 42, 'x'), isFalse);
    });

    test('delete maps to the broadcast and internal modes', () async {
      final broadcast = _RecordingService(
        '{"result":{"type":"chatItemsDeleted"}}',
      );
      expect(await broadcast.deleteMessage('@1', 7, forEveryone: true), isTrue);
      expect(broadcast.commands, ['/_delete item @1 7 broadcast']);

      final internal = _RecordingService(
        '{"result":{"type":"chatItemsDeleted"}}',
      );
      expect(await internal.deleteMessage('@1', 7, forEveryone: false), isTrue);
      expect(internal.commands, ['/_delete item @1 7 internal']);
    });

    test('delete reports core errors', () async {
      final service = _RecordingService('{"result":{"type":"chatCmdError"}}');
      expect(await service.deleteMessage('@1', 7, forEveryone: true), isFalse);
    });
  });

  group('meta flags', () {
    test('buildTimeline carries edited, editable and deletable', () {
      final timeline = buildTimeline(
        [
          textItem(
            text: 'old text',
            time: _now,
            fromMe: true,
            edited: true,
            editable: true,
            deletable: true,
          ),
        ],
        now: _now,
        chatName: 'Alice',
      );
      final item = timeline.last;
      expect(item.edited, isTrue);
      expect(item.editable, isTrue);
      expect(item.deletable, isTrue);
    });
  });

  group('message actions', () {
    testWidgets('an editable own message offers Edit and Delete', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        items: [
          textItem(
            text: 'fix the typo',
            time: _now,
            fromMe: true,
            editable: true,
            deletable: true,
          ),
        ],
      );
      await _openMenu(tester, 'fix the typo');
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('Edit is hidden once the core refuses it', (tester) async {
      await _pumpShell(
        tester,
        items: [
          textItem(text: 'too old', time: _now, fromMe: true),
        ],
      );
      await _openMenu(tester, 'too old');
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('deep-linking flags are not required for Delete', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        items: [textItem(text: 'from Alice', time: _now)],
      );
      await _openMenu(tester, 'from Alice');
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('editing', () {
    testWidgets('Edit prefills the composer and saves through the core', (
      tester,
    ) async {
      final core = await _pumpShell(
        tester,
        items: [
          textItem(
            text: 'first version',
            time: _now,
            fromMe: true,
            editable: true,
            deletable: true,
          ),
        ],
      );

      await _openMenu(tester, 'first version');
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Telegram's edit header plus the original markdown source in the field.
      expect(find.text('Edit message'), findsOneWidget);
      expect(
        tester.widget<TextField>(_composer()).controller?.text,
        'first version',
      );
      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.enterText(_composer(), 'second version');
      await tester.tap(find.byIcon(Icons.check));
      await tester.pump(const Duration(milliseconds: 400));

      expect(core.edits, hasLength(1));
      expect(core.edits.single.chatRef, '@1');
      expect(core.edits.single.text, 'second version');
      expect(find.text('Edit message'), findsNothing);
      expect(find.text('second version'), findsWidgets);
      expect(find.byKey(const ValueKey('edited-label')), findsOneWidget);
    });

    testWidgets('X cancels editing and clears the field', (tester) async {
      final core = await _pumpShell(
        tester,
        items: [
          textItem(
            text: 'draft me',
            time: _now,
            fromMe: true,
            editable: true,
          ),
        ],
      );

      await _openMenu(tester, 'draft me');
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cancel editing'));
      await tester.pumpAndSettle();

      expect(find.text('Edit message'), findsNothing);
      expect(tester.widget<TextField>(_composer()).controller?.text, '');
      expect(core.edits, isEmpty);
    });
  });

  group('deleting', () {
    testWidgets('broadcast delete asks and reaches the core', (tester) async {
      final core = await _pumpShell(
        tester,
        items: [
          textItem(
            text: 'delete me',
            time: _now,
            fromMe: true,
            editable: true,
            deletable: true,
          ),
        ],
      );

      await _openMenu(tester, 'delete me');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete message?'), findsOneWidget);
      expect(
        find.text('This message will be deleted for everyone.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('delete-for-everyone')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(core.deletions, hasLength(1));
      expect(core.deletions.single.forEveryone, isTrue);
      expect(find.text('delete me'), findsNothing);
    });

    testWidgets('a message the core cannot broadcast only deletes locally', (
      tester,
    ) async {
      final core = await _pumpShell(
        tester,
        items: [
          textItem(text: 'just for me', time: _now),
        ],
      );

      await _openMenu(tester, 'just for me');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('delete-for-everyone')), findsNothing);
      expect(
        find.text('This message will be deleted for you.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('delete-for-me')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(core.deletions.single.forEveryone, isFalse);
      expect(find.text('just for me'), findsNothing);
    });

    testWidgets('cancel leaves the message alone', (tester) async {
      final core = await _pumpShell(
        tester,
        items: [textItem(text: 'keep me', time: _now)],
      );

      await _openMenu(tester, 'keep me');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(core.deletions, isEmpty);
      expect(find.text('keep me'), findsOneWidget);
    });
  });
}
