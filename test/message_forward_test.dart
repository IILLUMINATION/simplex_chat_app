import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/providers/persistent_store.dart';
import 'package:tanglex_chat/src/service/tanglex_service.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/messenger_shell.dart';

import 'support/fake_chat_core.dart';

final _now = DateTime(2026, 10, 29, 11, 0);

final _theme = buildAppTheme(
  const AppThemeSettings(fontFamily: 'Roboto'),
  Brightness.light,
);

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

final _chats = [
  ChatPreview(
    chatRef: '@1',
    chatType: 'contact',
    displayName: 'Alice Bergström',
    timestamp: _now.microsecondsSinceEpoch,
    connStatusType: 'ready',
  ),
  ChatPreview(
    chatRef: '#7',
    chatType: 'group',
    displayName: 'Meander Dev',
    lastMessage: 'pushed the FFI bridge',
    timestamp: _now.microsecondsSinceEpoch,
    memberCount: 12,
  ),
  ChatPreview(
    chatRef: '@2',
    chatType: 'contact',
    displayName: 'Dan',
    timestamp: _now.microsecondsSinceEpoch,
    connStatusType: 'ready',
  ),
];

Future<FakeChatCore> _pumpShell(
  WidgetTester tester, {
  List<Map<String, dynamic>>? items,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final core = FakeChatCore(
    chats: _chats,
    messages: {
      '@1': items ??
          [
            textItem(text: 'first version', time: _now, fromMe: true),
            textItem(
              text: 'see you at 8',
              time: _now.add(const Duration(minutes: 1)),
              fromMe: true,
            ),
          ],
      '#7': <Map<String, dynamic>>[],
      '@2': <Map<String, dynamic>>[],
    },
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

Future<void> _openMenu(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  group('core command', () {
    test('forward uses the documented /_forward grammar', () async {
      final service = _RecordingService(
        '{"result":{"type":"newChatItems","chatItems":[]}}',
      );
      final ok = await service.forwardMessages('@2', '@1', [42]);
      expect(ok, isTrue);
      expect(service.commands, ['/_forward @2 @1 42']);
    });

    test('several items travel as one comma-separated list', () async {
      final service = _RecordingService('{"result":{"type":"newChatItems"}}');
      expect(await service.forwardMessages('#7', '@1', [11, 12, 13]), isTrue);
      expect(service.commands, ['/_forward #7 @1 11,12,13']);
    });

    test('nothing to forward never reaches the core', () async {
      final service = _RecordingService('{"result":{"type":"newChatItems"}}');
      expect(await service.forwardMessages('@2', '@1', const []), isFalse);
      expect(service.commands, isEmpty);
    });

    test('core errors report failure', () async {
      final service = _RecordingService(
        '{"error":{"type":"chatError","errorType":{"type":"noChatItem"}}}',
      );
      expect(await service.forwardMessages('@2', '@1', [42]), isFalse);
    });
  });

  group('forwarded header', () {
    test('the meta keeps the source chat name', () {
      final timeline = buildTimeline(
        [
          textItem(
            text: 'see you at 8',
            time: _now,
            fromMe: true,
            forwarded: true,
            forwardedFrom: 'Alice Bergström',
          ),
        ],
        now: _now,
        chatName: 'Dan',
      );
      final item = timeline.last;
      expect(item.forwarded, isTrue);
      expect(item.forwardedFrom, 'Alice Bergström');
    });

    testWidgets('the bubble paints Forwarded from <chat>', (tester) async {
      await _pumpShell(
        tester,
        items: [
          textItem(
            text: 'see you at 8',
            time: _now,
            fromMe: true,
            forwarded: true,
            forwardedFrom: 'Meander Dev',
          ),
        ],
      );

      expect(find.byKey(const ValueKey('forwarded-label')), findsOneWidget);
      expect(find.text('Forwarded from Meander Dev'), findsOneWidget);
    });

    testWidgets('a forward of unknown origin stays generic', (tester) async {
      await _pumpShell(
        tester,
        items: [
          textItem(
            text: 'see you at 8',
            time: _now,
            fromMe: true,
            forwarded: true,
          ),
        ],
      );

      expect(find.text('Forwarded'), findsOneWidget);
    });
  });

  group('forward picker', () {
    testWidgets('the menu offers Forward next to Copy text', (tester) async {
      await _pumpShell(tester);
      await _openMenu(tester, 'see you at 8');

      expect(find.text('Forward'), findsOneWidget);
      expect(find.text('Copy text'), findsOneWidget);
      expect(find.byKey(const ValueKey('forward-dialog')), findsNothing);
    });

    testWidgets('picking a chat forwards through the core', (tester) async {
      final core = await _pumpShell(tester);
      await _openMenu(tester, 'see you at 8');
      await tester.tap(find.text('Forward'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('forward-dialog')), findsOneWidget);
      expect(find.text('Forward to'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('forward-target-#7')));
      await tester.pumpAndSettle();

      expect(core.forwards, hasLength(1));
      expect(core.forwards.single.toChatRef, '#7');
      expect(core.forwards.single.fromChatRef, '@1');
      expect(
        core.forwards.single.itemId,
        _now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      );
      expect(find.byKey(const ValueKey('forward-dialog')), findsNothing);
      expect(find.text('Forwarded to Meander Dev'), findsOneWidget);
      // The copy landed in the target chat, exactly like `/_forward`.
      expect(
        core.messages['#7']!.map((raw) => (raw['meta'] as Map)['itemText']),
        contains('see you at 8'),
      );
    });

    testWidgets('search narrows the chat list', (tester) async {
      await _pumpShell(tester);
      await _openMenu(tester, 'see you at 8');
      await tester.tap(find.text('Forward'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('forward-target-@2')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('forward-search')),
        'dan',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('forward-target-@2')), findsOneWidget);
      expect(find.byKey(const ValueKey('forward-target-#7')), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('forward-search')),
        'zzz',
      );
      await tester.pumpAndSettle();
      expect(find.text('No chats found'), findsOneWidget);
    });

    testWidgets('closing the picker forwards nothing', (tester) async {
      final core = await _pumpShell(tester);
      await _openMenu(tester, 'see you at 8');
      await tester.tap(find.text('Forward'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(core.forwards, isEmpty);
      expect(find.byKey(const ValueKey('forward-dialog')), findsNothing);
    });
  });

  testWidgets('the current chat is selectable as a destination', (
    tester,
  ) async {
    final core = await _pumpShell(tester);
    await _openMenu(tester, 'see you at 8');
    await tester.tap(find.text('Forward'));
    await tester.pumpAndSettle();

    // Telegram keeps the source chat in the list.
    expect(
      find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.text('Alice Bergström'),
      ),
      findsWidgets,
    );
    await tester.tap(find.byKey(const ValueKey('forward-target-@1')));
    await tester.pumpAndSettle();

    expect(core.forwards.single.toChatRef, '@1');
  });
}
