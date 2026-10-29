import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/notifications/notification_sink.dart';
import 'package:tanglex_chat/src/providers/persistent_store.dart';

import 'support/fake_chat_core.dart';

final _now = DateTime(2026, 10, 28, 21, 0);

ChatPreview _chat(String ref, String name) => ChatPreview(
  chatRef: ref,
  chatType: 'contact',
  displayName: name,
  timestamp: _now.microsecondsSinceEpoch,
  connStatusType: 'ready',
  contactStatus: 'active',
);

ChatPreview _withMail(
  ChatPreview chat, {
  required int unread,
  required String preview,
  bool muted = false,
}) => ChatPreview(
  chatRef: chat.chatRef,
  chatType: chat.chatType,
  displayName: chat.displayName,
  lastMessage: preview,
  timestamp: chat.timestamp,
  unreadCount: unread,
  connStatusType: chat.connStatusType,
  contactStatus: chat.contactStatus,
  muted: muted,
);

class _FakeSink implements NotificationSink {
  final List<({String chatRef, String title, String body})> shown = [];

  @override
  Future<void> showMessage({
    required String chatRef,
    required String title,
    required String body,
  }) async {
    shown.add((chatRef: chatRef, title: title, body: body));
  }
}

({ProviderContainer container, FakeChatCore core, _FakeSink sink}) _setup({
  List<ChatPreview>? chats,
}) {
  final core = FakeChatCore(
    chats: chats ?? [_chat('@1', 'Alice'), _chat('@2', 'Bob')],
    now: _now,
  );
  final sink = _FakeSink();
  final container = ProviderContainer(
    overrides: [
      chatCoreProvider.overrideWithValue(core),
      notificationSinkProvider.overrideWithValue(sink),
      clockProvider.overrideWithValue(() => _now),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, core: core, sink: sink);
}

void main() {
  test('new mail notifies the chat but never the open conversation', () async {
    final env = _setup();
    await env.container.read(chatsProvider.future);
    env.container.read(activeChatRefProvider.notifier).state = '@1';

    env.core.chats[1] = _withMail(
      env.core.chats[1],
      unread: 2,
      preview: 'hello there',
    );
    await env.container.read(chatsProvider.notifier).refresh();

    expect(env.sink.shown, hasLength(1));
    expect(env.sink.shown.single.chatRef, '@2');
    expect(env.sink.shown.single.title, 'Bob');
    expect(env.sink.shown.single.body, 'hello there');

    // The same counter again is not a new message.
    await env.container.read(chatsProvider.notifier).refresh();
    expect(env.sink.shown, hasLength(1));
  });

  test('a muted chat stays silent and speaks again when unmuted', () async {
    final env = _setup();
    await env.container.read(chatsProvider.future);

    env.core.chats[1] = _withMail(
      env.core.chats[1],
      unread: 1,
      preview: 'psst',
      muted: true,
    );
    await env.container.read(chatsProvider.notifier).refresh();
    expect(env.sink.shown, isEmpty);

    env.core.chats[1] = _withMail(
      env.core.chats[1],
      unread: 2,
      preview: 'now unmuted',
    );
    await env.container.read(chatsProvider.notifier).refresh();
    expect(env.sink.shown, hasLength(1));
    expect(env.sink.shown.single.body, 'now unmuted');
  });

  test('mail that was already unread at launch stays silent', () async {
    final env = _setup(
      chats: [
        _chat('@1', 'Alice'),
        _withMail(
          _chat('@2', 'Bob'),
          unread: 3,
          preview: 'old news',
        ),
      ],
    );

    await env.container.read(chatsProvider.future);
    await env.container.read(chatsProvider.notifier).refresh();

    expect(env.sink.shown, isEmpty);
  });
}
