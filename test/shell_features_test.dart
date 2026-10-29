import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/providers/persistent_store.dart';
import 'package:tanglex_chat/src/shell/adaptive_shell.dart';
import 'package:tanglex_chat/src/shell/chat_list_panel.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/details_panel.dart';
import 'package:tanglex_chat/src/shell/messenger_shell.dart';
import 'package:tanglex_chat/src/shell/models.dart';
import 'package:tanglex_chat/src/shell/widgets/peer_avatar.dart';

import 'support/fake_chat_core.dart';

final _now = DateTime(2026, 10, 26, 15, 0);

final _theme = buildAppTheme(
  const AppThemeSettings(fontFamily: 'Roboto'),
  Brightness.light,
);

Widget _shell(FakeChatCore core, {Size size = const Size(1280, 800)}) {
  return ProviderScope(
    overrides: [
      chatCoreProvider.overrideWithValue(core),
      clockProvider.overrideWithValue(() => _now),
    ],
    child: AppThemeScope(
      theme: _theme,
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(size: size),
            child: const MessengerShell(),
          ),
        ),
      ),
    ),
  );
}

ChatPreview _directChat({
  String ref = '@1',
  String name = 'Alice',
  int? requestId,
}) {
  return ChatPreview(
    chatRef: ref,
    chatType: 'contact',
    displayName: name,
    timestamp: _now.microsecondsSinceEpoch,
    connStatusType: requestId == null ? 'ready' : null,
    contactStatus: 'active',
    embeddedContactRequestId: requestId,
  );
}

Future<FakeChatCore> _pumpShell(
  WidgetTester tester, {
  List<Map<String, dynamic>>? items,
  List<ChatPreview>? chats,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final core = FakeChatCore(
    chats: chats ?? [_directChat()],
    messages: {'@1': items ?? [textItem(text: 'original', time: _now)]},
    now: _now,
  );
  await tester.pumpWidget(_shell(core, size: size));
  await tester.pumpAndSettle();
  return core;
}

Finder _composer() => find.descendant(
  of: find.byType(ConversationPanel),
  matching: find.byType(TextField),
);

Future<void> _openMessageMenu(WidgetTester tester, Finder message) async {
  await tester.tap(message, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reply quotes the original item and shows it in the bubble', (
    tester,
  ) async {
    final items = [
      textItem(text: 'original', time: _now),
      textItem(
        text: 'latest',
        time: _now.add(const Duration(minutes: 1)),
      ),
    ];
    final core = await _pumpShell(tester, items: items);
    final quotedId =
        (items.first['meta'] as Map<String, dynamic>)['itemId'] as int;

    await _openMessageMenu(tester, find.text('original'));
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();

    // The reply bar above the composer previews the quoted message.
    expect(find.text('original'), findsNWidgets(2));

    await tester.enterText(_composer(), 'answer');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(core.sentTexts, ['answer']);
    expect(core.sentQuotedIds, [quotedId]);
    // Bubble quote + original bubble.
    expect(find.text('original'), findsNWidgets(2));
  });

  testWidgets('a reaction chip toggles on and off through the core', (
    tester,
  ) async {
    final items = [textItem(text: 'react to me', time: _now)];
    final core = await _pumpShell(tester, items: items);
    final itemId =
        (items.first['meta'] as Map<String, dynamic>)['itemId'] as int;

    await _openMessageMenu(tester, find.text('react to me'));
    await tester.tap(find.text('❤️'));
    await tester.pumpAndSettle();

    // The menu shows the emoji presentation, but the core only accepts the
    // bare U+2764 char (`mrEmojiChar` in simplex-chat).
    expect(core.reactionChanges, hasLength(1));
    expect(core.reactionChanges.single.itemId, itemId);
    expect(core.reactionChanges.single.emoji, '❤');
    expect(core.reactionChanges.single.add, isTrue);
    expect(find.text('❤️'), findsOneWidget);

    await tester.tap(find.text('❤️'));
    await tester.pumpAndSettle();

    expect(core.reactionChanges, hasLength(2));
    expect(core.reactionChanges.last.add, isFalse);
    expect(find.text('❤️'), findsNothing);
  });

  testWidgets('a new reaction chip pops in instead of snapping', (
    tester,
  ) async {
    final core = await _pumpShell(
      tester,
      items: [textItem(text: 'react to me', time: _now)],
    );
    expect(core, isNotNull);
    await _openMessageMenu(tester, find.text('react to me'));
    await tester.tap(find.text('👍'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final chip = find.byKey(const ValueKey('reaction-chip-👍'));
    expect(chip, findsOneWidget);
    final midScale = tester
        .widget<ScaleTransition>(
          find.descendant(of: chip, matching: find.byType(ScaleTransition)),
        )
        .scale
        .value;
    expect(midScale, lessThan(1));
    expect(midScale, greaterThan(0.6));

    await tester.pumpAndSettle();
    final settledScale = tester
        .widget<ScaleTransition>(
          find.descendant(of: chip, matching: find.byType(ScaleTransition)),
        )
        .scale
        .value;
    expect(settledScale, moreOrLessEquals(1, epsilon: 0.001));
  });

  testWidgets('hovering the reaction strip scales the emoji to 1.24', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      items: [textItem(text: 'hover me', time: _now)],
    );
    await _openMessageMenu(tester, find.text('hover me'));
    final emoji = find.byKey(const ValueKey('strip-emoji-👍'));
    expect(tester.widget<AnimatedScale>(emoji).scale, 1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(emoji));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(emoji).scale, 1.24);
    expect(
      tester.widget<AnimatedScale>(emoji).duration,
      const Duration(milliseconds: 200),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final mid = tester
        .widget<Transform>(
          find.descendant(of: emoji, matching: find.byType(Transform)).first,
        )
        .transform
        .entry(0, 0);
    expect(mid, greaterThan(1));
    expect(mid, lessThan(1.24));

    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(emoji).scale, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('reactions are drawn inside the message bubble', (tester) async {
    final items = [
      textItem(
        text: 'react to me',
        time: _now,
        reactions: [
          {
            'reaction': {'type': 'emoji', 'emoji': '❤'},
            'totalReacted': 2,
            'userReacted': true,
          },
        ],
      ),
    ];
    await _pumpShell(tester, items: items);
    final itemId =
        (items.first['meta'] as Map<String, dynamic>)['itemId'] as int;

    // Telegram appends the reaction tags inside the bubble instead of
    // floating them below it (`history_view_message.cpp`).
    final bubble = tester.getRect(
      find.byKey(ValueKey('message-bubble-$itemId')),
    );
    final chip = tester.getRect(find.byKey(const ValueKey('reaction-chip-❤')));
    expect(bubble.contains(chip.center), isTrue);
    // `reactStripHeight`-style tag: 22px tall.
    expect(chip.height, 22);
  });

  testWidgets('unknown reactions render as a question mark', (tester) async {
    final items = [
      textItem(
        text: 'future reaction',
        time: _now,
        reactions: [
          {
            'reaction': {'type': 'icecream'},
            'totalReacted': 2,
            'userReacted': false,
          },
          {
            'reaction': {'type': 'emoji', 'emoji': '❤️'},
            'totalReacted': 1,
            'userReacted': true,
          },
        ],
      ),
    ];
    await _pumpShell(tester, items: items);

    expect(find.text('?'), findsOneWidget);
    // A heart sent by another client still renders as an emoji.
    expect(find.text('❤️'), findsOneWidget);
  });

  testWidgets('a pending contact request is listed and can be accepted', (
    tester,
  ) async {
    final core = await _pumpShell(
      tester,
      chats: [
        _directChat(name: 'sa', requestId: 1),
        ChatPreview(
          chatRef: '#7',
          chatType: 'group',
          displayName: 'Meander Dev',
          timestamp: _now.subtract(const Duration(hours: 1)).microsecondsSinceEpoch,
        ),
      ],
      items: const [],
    );

    expect(find.text('CONTACT REQUESTS'), findsOneWidget);
    expect(find.text('Contact request'), findsOneWidget);
    // Accept/decline replace the composer until the request is handled.
    expect(find.byTooltip('Send'), findsNothing);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept incognito'));
    await tester.pumpAndSettle();

    expect(core.acceptedRequests, hasLength(1));
    expect(core.acceptedRequests.single.requestId, 1);
    expect(core.acceptedRequests.single.incognito, isTrue);
  });

  testWidgets('a contact request can be declined', (tester) async {
    final core = await _pumpShell(
      tester,
      chats: [_directChat(name: 'sa', requestId: 3)],
      items: const [],
    );

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();

    expect(core.rejectedRequests, [3]);
    expect(core.acceptedRequests, isEmpty);
  });

  testWidgets('service messages stay narrow and centered', (tester) async {
    const long =
        'The group was created and every member joined from a different '
        'device while the network was reconnecting for a while';
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppThemeScope(
        theme: _theme,
        child: MaterialApp(
          home: Scaffold(
            body: ConversationPanel(
              chat: const ChatSummary(
                id: '@1',
                name: 'Alice',
                preview: '',
                time: '',
              ),
              messages: const [
                MessageItem(text: long, time: '', isSystem: true),
              ],
              canSend: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final size = tester.getSize(find.text(long));
    // Telegram's service block tops out at 542px (498px of text plus
    // `msgServicePadding`), `history_view_service_message.cpp`.
    expect(size.width, lessThanOrEqualTo(498));
  });

  testWidgets('a photo bubble sizes from the file and overlays its time', (
    tester,
  ) async {
    final item = imageItem(
      time: _now,
      fileName: 'photo_2026-10-26_14-31-02.jpg',
      size: 412000,
    );
    await _pumpShell(
      tester,
      size: const Size(390, 844),
      items: [item],
    );
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await tester.pumpAndSettle();

    final bubble = find.byKey(
      ValueKey('message-bubble-${_now.millisecondsSinceEpoch}'),
    );
    final size = tester.getSize(bubble);

    // The demo preview is 640x360 and Telegram sizes photo bubbles from the
    // file's aspect ratio (`history_view_photo.cpp`), so no caption means the
    // bubble is nothing but the 16:9 photo.
    expect(size.height, closeTo(size.width * 9 / 16, 1));

    final image = tester.getSize(find.byType(RawImage));
    expect(image, size);

    final time = tester.getRect(find.text('15:00'));
    final radius = tester.getRect(bubble);
    expect(time.right, lessThan(radius.right - 4));
    expect(time.bottom, greaterThan(radius.bottom - 24));
  });

  testWidgets('header opens chat info on a narrow window', (tester) async {
    await _pumpShell(tester, size: const Size(520, 800));

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('conversation-header')));
    await tester.pumpAndSettle();

    expect(find.byType(DetailsPanel), findsOneWidget);
  });

  testWidgets('the chat list divider widens and collapses like Telegram', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppThemeScope(
        theme: _theme,
        child: MaterialApp(
          home: Scaffold(
            body: AdaptiveShell(
              chatList: const SizedBox.expand(),
              conversation: const SizedBox.expand(),
              emptyConversation: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final column = find.byKey(const ValueKey('chat-list-column'));
    final handle = find.byKey(const ValueKey('chat-list-resize'));
    final initial = tester.getSize(column).width;
    expect(initial, closeTo(1200 * 5 / 14, 0.5));

    await tester.drag(handle, const Offset(100, 0), touchSlopX: 0);
    await tester.pumpAndSettle();
    expect(tester.getSize(column).width, closeTo(initial + 100, 0.5));

    // Dragging past half of the minimal column collapses the list to the
    // avatar rail (`dialogsSmallColumnWidth` = 10 + 46 + 10).
    await tester.drag(handle, const Offset(-400, 0), touchSlopX: 0);
    await tester.pumpAndSettle();
    expect(tester.getSize(column).width, 66);

    // Dragging back expands to the minimal column width instead of growing
    // pixel by pixel — same snap as Telegram's ratio-based resize.
    await tester.drag(handle, const Offset(100, 0), touchSlopX: 0);
    await tester.pumpAndSettle();
    expect(tester.getSize(column).width, 260);

    // No double-click reset in Telegram: the splitter stays where it was.
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(tester.getSize(column).width, 260);
  });

  testWidgets('the chat list divider keeps up with a fast pointer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppThemeScope(
        theme: _theme,
        child: MaterialApp(
          home: Scaffold(
            body: AdaptiveShell(
              chatList: const SizedBox.expand(),
              conversation: const SizedBox.expand(),
              emptyConversation: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final column = find.byKey(const ValueKey('chat-list-column'));
    final handle = find.byKey(const ValueKey('chat-list-resize'));
    final before = tester.getSize(column).width;

    // Several pointer moves land between two frames, like a 125Hz mouse.
    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(20, 0));
    }
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(20, 0));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getSize(column).width, closeTo(before + 240, 1));
  });

  testWidgets('the compact chat list shows avatars only', (tester) async {
    final core = FakeChatCore(
      chats: demoChats(_now),
      messages: demoConversations(_now),
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
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 66,
                height: 700,
                child: ChatListPanel(
                  chats: [
                    const ChatSummary(
                      id: '@1',
                      name: 'Alice Bergström',
                      preview: 'hello',
                      time: '15:00',
                      unread: 3,
                    ),
                    const ChatSummary(
                      id: '@2',
                      name: 'Meander Dev',
                      preview: 'bye',
                      time: '14:00',
                    ),
                  ],
                  selectedId: '@1',
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice Bergström'), findsNothing);
    expect(find.text('TangleX'), findsNothing);
    expect(find.byType(PeerAvatar), findsNWidgets(2));
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('the details divider drags and clamps like Telegram', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppThemeScope(
        theme: _theme,
        child: MaterialApp(
          home: Scaffold(
            body: AdaptiveShell(
              chatList: const SizedBox.expand(),
              conversation: const SizedBox.expand(),
              emptyConversation: const SizedBox.expand(),
              details: const SizedBox.expand(),
              detailsOpen: true,
              chatSelected: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final column = find.byKey(const ValueKey('details-column'));
    final handle = find.byKey(const ValueKey('details-resize'));
    expect(tester.getSize(column).width, 292);

    await tester.drag(handle, const Offset(-60, 0), touchSlopX: 0);
    await tester.pumpAndSettle();
    expect(tester.getSize(column).width, closeTo(352, 0.5));

    // `columnMaximalWidthThird` bounds the details column.
    await tester.drag(handle, const Offset(-100, 0), touchSlopX: 0);
    await tester.pumpAndSettle();
    expect(tester.getSize(column).width, 392);

    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(tester.getSize(column).width, 392);
  });

  testWidgets('hovering a message does not reveal a reply shortcut', (
    tester,
  ) async {
    await _pumpShell(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('original')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Reply'), findsNothing);
    expect(find.byIcon(Icons.reply), findsNothing);
  });

  testWidgets('the message actions card copies the text', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpShell(tester);
    await _openMessageMenu(tester, find.text('original'));

    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('❤️'), findsOneWidget);
    expect(find.text('?'), findsNothing);

    await tester.tap(find.text('Copy text'));
    await tester.pumpAndSettle();

    final copy = calls.where((call) => call.method == 'Clipboard.setData');
    expect(copy, hasLength(1));
    expect((copy.single.arguments as Map)['text'], 'original');
    expect(find.text('Copy text'), findsNothing);
  });

  testWidgets('the action menu follows Telegram reaction strip metrics', (
    tester,
  ) async {
    await _pumpShell(tester);
    await _openMessageMenu(tester, find.text('original'));

    // `history_view_reactions_selector.cpp`: 40px strip, 32px cells, 7px skip
    // => 8 * 32 + 7 * 7 + 6px padding.
    expect(
      tester.getSize(find.byKey(const ValueKey('reaction-strip'))),
      const Size(312, 40),
    );
    final strip = tester.getRect(find.byKey(const ValueKey('reaction-strip')));
    final card = tester.getRect(find.byKey(const ValueKey('actions-card')));
    expect(card.width, 244);
    expect(card.center.dx, closeTo(strip.center.dx, 0.5));
  });

  testWidgets('the action menu pops out of the anchor corner', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.text('original'), buttons: kSecondaryButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // `st::defaultPanelAnimation` starts at 50% width / 30% height.
    final growing = tester.widget<Transform>(
      find.byKey(const ValueKey('message-actions-pop')),
    );
    // `getMaxScaleOnAxis` would always report 1 because the z axis stays 1.
    expect(growing.transform.entry(0, 0), lessThan(1));
    expect(growing.transform.entry(1, 1), lessThan(1));

    await tester.pumpAndSettle();
    final settled = tester.widget<Transform>(
      find.byKey(const ValueKey('message-actions-pop')),
    );
    expect(settled.transform.entry(0, 0), closeTo(1, 0.001));
    expect(settled.transform.entry(1, 1), closeTo(1, 0.001));
  });

  testWidgets('the composer follows the Telegram flat-field metrics', (
    tester,
  ) async {
    await _pumpShell(tester);

    expect(tester.getSize(find.byTooltip('Attach')), const Size(44, 46));
    expect(tester.getSize(find.byTooltip('Emoji')), const Size(44, 46));
    expect(tester.getSize(find.byTooltip('Send')), const Size(44, 46));

    final field = _composer();
    expect(tester.getSize(field).height, 36);

    await tester.enterText(field, 'one\ntwo\nthree\nfour\nfive');
    await tester.pumpAndSettle();
    expect(tester.getSize(field).height, lessThanOrEqualTo(72));
  });

  testWidgets('incoming mail never yanks a scrolled-up history', (
    tester,
  ) async {
    final items = [
      for (var i = 0; i < 40; i++) textItem(text: 'message $i', time: _now),
    ];
    final core = await _pumpShell(tester, items: items);

    final list = find.descendant(
      of: find.byType(ConversationPanel),
      matching: find.byType(ListView),
    );
    await tester.drag(list, const Offset(0, 600));
    await tester.pumpAndSettle();
    final controller = tester.widget<ListView>(list).controller!;
    final before = controller.offset;
    expect(before, lessThan(controller.position.maxScrollExtent));

    core.messages['@1']!.add(textItem(text: 'incoming', time: _now));
    core.emitEvent('newChatItems');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MessengerShell)),
    );
    final timeline = container.read(messagesProvider('@1')).value!;
    expect(timeline.where((item) => item.text == 'incoming'), hasLength(1));
    expect(controller.offset, before);
  });

  testWidgets('a pinned history stays at the bottom on incoming mail', (
    tester,
  ) async {
    final items = [
      for (var i = 0; i < 40; i++) textItem(text: 'message $i', time: _now),
    ];
    final core = await _pumpShell(tester, items: items);

    final list = find.descendant(
      of: find.byType(ConversationPanel),
      matching: find.byType(ListView),
    );
    final controller = tester.widget<ListView>(list).controller!;
    expect(controller.offset, controller.position.maxScrollExtent);

    core.messages['@1']!.add(textItem(text: 'fresh', time: _now));
    core.emitEvent('newChatItems');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('fresh'), findsOneWidget);
    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('sending from above slides the history to the bottom', (
    tester,
  ) async {
    final items = [
      for (var i = 0; i < 40; i++) textItem(text: 'message $i', time: _now),
    ];
    await _pumpShell(tester, items: items);

    final list = find.descendant(
      of: find.byType(ConversationPanel),
      matching: find.byType(ListView),
    );
    await tester.drag(list, const Offset(0, 600));
    await tester.pumpAndSettle();
    final controller = tester.widget<ListView>(list).controller!;
    final before = controller.offset;

    await tester.enterText(_composer(), 'mine');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final target = controller.position.maxScrollExtent;
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.offset, greaterThan(before));
    expect(controller.offset, lessThan(target - 1));

    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('the jump-down button follows Telegram corner-button rules', (
    tester,
  ) async {
    final items = [
      for (var i = 0; i < 40; i++) textItem(text: 'message $i', time: _now),
    ];
    final core = await _pumpShell(tester, items: items);

    final list = find.descendant(
      of: find.byType(ConversationPanel),
      matching: find.byType(ListView),
    );
    final controller = tester.widget<ListView>(list).controller!;
    double opacity() => tester
        .widget<AnimatedOpacity>(find.byKey(const ValueKey('jumpDown')))
        .opacity;

    expect(opacity(), 0);

    await tester.drag(list, const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(find.byKey(const ValueKey('jumpDownBadge')), findsNothing);

    core.messages['@1']!.add(textItem(text: 'incoming', time: _now));
    core.emitEvent('newChatItems');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final badge = find.byKey(const ValueKey('jumpDownBadge'));
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.text('1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('jumpDown')));
    await tester.pumpAndSettle();

    expect(controller.offset, controller.position.maxScrollExtent);
    expect(opacity(), 0);
    expect(badge, findsNothing);
  });

  testWidgets('the attach menu offers photos and files', (tester) async {
    var photos = 0;
    var files = 0;
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppThemeScope(
        theme: _theme,
        child: MaterialApp(
          home: Scaffold(
            body: ConversationPanel(
              chat: const ChatSummary(
                id: '@1',
                name: 'Alice',
                preview: '',
                time: '',
              ),
              messages: const [],
              onSend: (_, {quotedItemId, reply}) {},
              onAttachPhoto: () => photos++,
              onAttachFile: () => files++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);

    await tester.tap(find.text('Photo'));
    await tester.pumpAndSettle();
    expect(photos, 1);

    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(files, 1);
  });
}
