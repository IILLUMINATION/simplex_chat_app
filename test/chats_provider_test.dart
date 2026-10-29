import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/providers/persistent_store.dart';

import 'support/fake_chat_core.dart';

ChatPreview _direct(String ref, String name, {int? requestId}) => ChatPreview(
  chatRef: ref,
  chatType: 'contact',
  displayName: name,
  contactStatus: 'active',
  connStatusType: requestId == null ? 'ready' : null,
  embeddedContactRequestId: requestId,
);

void main() {
  final now = DateTime(2026, 10, 27, 12);

  ProviderContainer containerFor(FakeChatCore core) {
    final container = ProviderContainer(
      overrides: [
        chatCoreProvider.overrideWithValue(core),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a contact that finishes connecting refreshes the chat list', () async {
    final core = FakeChatCore(
      chats: [_direct('@1', 'Alice')],
      now: now,
    );
    final container = containerFor(core);
    expect(await container.read(chatsProvider.future), hasLength(1));

    // The core reports a newly connected contact only through this event.
    core.chats.add(_direct('@2', 'Bob'));
    core.emitEvent('contactConnected');
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final names = container
        .read(chatsProvider)
        .valueOrNull!
        .map((chat) => chat.name);
    expect(names, contains('Bob'));
  });

  test('note folders and unknown chats are not rendered as dead rows', () async {
    final core = FakeChatCore(
      chats: [
        _direct('@1', 'Alice'),
        const ChatPreview(chatRef: '@?', chatType: 'local'),
        const ChatPreview(chatRef: '@?', chatType: 'unknown'),
      ],
      now: now,
    );
    final container = containerFor(core);

    final chats = await container.read(chatsProvider.future);
    expect(chats.map((chat) => chat.name), ['Alice']);
  });

  test('a pending contact request stays in the list awaiting acceptance',
      () async {
    final core = FakeChatCore(
      chats: [_direct('@7', 'Sam', requestId: 7)],
      now: now,
    );
    final container = containerFor(core);

    final chats = await container.read(chatsProvider.future);
    expect(chats, hasLength(1));
    expect(chats.single.needsAccept, isTrue);
    expect(chats.single.requestId, 7);
    expect(chats.single.subtitle, 'contact request');
    expect(chats.single.canSend, isFalse);
  });

  test('profile and chat settings follow the SimpleX API shape', () {
    final preview = ChatPreview.fromJson({
      'unreadCount': 3,
      'chatInfo': {
        'type': 'direct',
        'contact': {
          'contactId': 5,
          'localDisplayName': 'alice',
          'displayName': 'Alice',
          'contactStatus': 'active',
          'profile': {
            'displayName': 'Alice',
            'fullName': 'Alice Smith',
            'shortDescr': 'Keys and coffee',
          },
          'activeConn': {
            'connStatus': {'type': 'ready'},
            'connPQEnabled': true,
          },
          'chatSettings': {'enableNtfs': 'none', 'favorite': true},
        },
      },
      'chatItems': [],
    });

    expect(preview.chatRef, '@5');
    expect(preview.fullName, 'Alice Smith');
    expect(preview.shortDescr, 'Keys and coffee');
    expect(preview.quantumResistant, isTrue);
    // The core writes MsgFilter as a bare string, not {"type": ...}.
    expect(preview.muted, isTrue);
    expect(preview.pinned, isTrue);
  });

  test('a group carries its description and member count', () {
    final preview = ChatPreview.fromJson({
      'chatInfo': {
        'type': 'group',
        'group': {
          'groupId': 7,
          'localDisplayName': 'meander',
          'groupProfile': {
            'displayName': 'Meander Dev',
            'shortDescr': 'Build logs',
            'description': 'Welcome to the build channel',
          },
          'groupSummary': {'currentMembers': 12},
          'chatSettings': {'enableNtfs': 'all', 'favorite': false},
        },
      },
    });

    expect(preview.chatRef, '#7');
    expect(preview.displayName, 'Meander Dev');
    expect(preview.shortDescr, 'Build logs');
    expect(preview.memberCount, 12);
    expect(preview.muted, isFalse);
  });
}
