import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/shell/models.dart';

import 'support/fake_chat_core.dart';

Map<String, dynamic> _groupItem({
  required String text,
  required DateTime time,
  required String sender,
}) {
  return {
    'chatDir': {
      'type': 'groupRcv',
      'groupMember': {
        'localDisplayName': sender.toLowerCase(),
        'memberProfile': {'displayName': sender},
      },
    },
    'meta': {
      'itemTs': time.toUtc().toIso8601String(),
      'itemText': text,
      'itemStatus': {'type': 'rcvNew'},
    },
    'content': {
      'type': 'rcvMsgContent',
      'msgContent': {'type': 'text', 'text': text},
    },
  };
}

void main() {
  final now = DateTime(2026, 10, 26, 15, 0);

  test('separates days and maps core statuses to ticks', () {
    final yesterday = DateTime(2026, 10, 25, 23, 50);
    final timeline = buildTimeline([
      textItem(text: 'old', time: yesterday),
      textItem(text: 'new', time: now, fromMe: true, status: 'sndRcvd'),
      textItem(text: 'pending', time: now, fromMe: true, status: 'sndNew'),
    ], now: now);

    final separators = timeline
        .where((m) => m.isDateSeparator)
        .map((m) => m.text)
        .toList();
    expect(separators, ['Yesterday', 'Today']);

    final outgoing = timeline.where((m) => m.outgoing).toList();
    expect(outgoing[0].status, MessageStatus.delivered);
    expect(outgoing[1].status, MessageStatus.sending);
  });

  test('reads the group member name as the bubble author', () {
    final timeline = buildTimeline([
      _groupItem(text: 'hello', time: now, sender: 'Nikita'),
      _groupItem(
        text: 'hi',
        time: now.add(const Duration(minutes: 1)),
        sender: 'Maria',
      ),
    ], now: now);

    final messages = timeline.where((m) => !m.isDateSeparator).toList();
    expect(messages.map((m) => m.sender), ['Nikita', 'Maria']);
    // Different authors never share a visual group.
    expect(messages[0].firstInGroup, isTrue);
    expect(messages[0].lastInGroup, isTrue);
    expect(messages[1].firstInGroup, isTrue);
  });

  test('groups consecutive messages from the same author', () {
    final timeline = buildTimeline([
      textItem(text: 'one', time: now),
      textItem(text: 'two', time: now.add(const Duration(minutes: 1))),
      textItem(text: 'three', time: now.add(const Duration(minutes: 30))),
    ], now: now);

    final messages = timeline.where((m) => !m.isDateSeparator).toList();
    expect(messages[0].firstInGroup, isTrue);
    expect(messages[0].lastInGroup, isFalse);
    expect(messages[1].firstInGroup, isFalse);
    expect(messages[1].lastInGroup, isTrue);
    // A long pause starts a new group.
    expect(messages[2].firstInGroup, isTrue);
  });

  test('v7 chatBanner items are not rendered as messages', () {
    final banner = {
      'chatDir': {'type': 'directSnd'},
      'meta': {
        'itemId': 23,
        'itemTs': '1970-01-01T00:00:00Z',
        'itemText': 'chat banner',
        'itemStatus': {'type': 'sndNew'},
      },
      'content': {'type': 'chatBanner'},
      'reactions': [],
    };
    final timeline = buildTimeline([
      banner,
      textItem(text: 'hello', time: now),
    ], now: now);

    expect(timeline.where((m) => m.isSystem), isEmpty);
    expect(timeline.where((m) => m.isDateSeparator), hasLength(1));
    expect(timeline.map((m) => m.text), contains('hello'));
  });

  test('quotes are attributed from chatDir, never a placeholder label', () {
    final toPeer = textItem(
      text: 'answer',
      time: now,
      fromMe: true,
      status: 'sndSent',
      quoteText: 'original',
    );
    final toSelf = textItem(
      text: 'follow-up',
      time: now.add(const Duration(minutes: 1)),
      fromMe: true,
      status: 'sndSent',
      quoteText: 'mine',
      quoteDir: 'directSnd',
    );
    final group = _groupItem(
      text: 'group answer',
      time: now.add(const Duration(minutes: 2)),
      sender: 'Maria',
    );
    group['quotedItem'] = {
      'chatDir': {
        'type': 'groupRcv',
        'groupMember': {
          'localAlias': '',
          'memberProfile': {'displayName': 'Nikita'},
        },
      },
      'content': {'text': 'group original'},
      'itemId': 7,
    };

    final timeline = buildTimeline(
      [toPeer, toSelf, group],
      now: now,
      chatName: 'Alice',
    );
    final replies = timeline
        .where((m) => !m.isDateSeparator && m.reply != null)
        .toList();

    expect(replies[0].reply!.author, 'Alice');
    expect(replies[1].reply!.author, 'You');
    expect(replies[2].reply!.author, 'Nikita');
    for (final message in replies) {
      expect(message.reply!.author, isNot('Reply'));
    }
  });

  test('items sharing a timestamp keep the core order', () {
    // More than 32 entries so Dart takes the unstable quicksort path; bursts
    // of same-second items must not shuffle the history.
    final items = [
      for (var i = 0; i < 40; i++) textItem(text: 'burst $i', time: now),
    ];
    final timeline = buildTimeline(items, now: now);
    final texts = timeline
        .where((m) => !m.isDateSeparator)
        .map((m) => m.text)
        .toList();

    expect(texts, [for (var i = 0; i < 40; i++) 'burst $i']);
  });

  test('epochs from the chat list survive the micro/milli/second split', () {
    expect(epochToDateTime(0), isNull);
    expect(
      epochToDateTime(DateTime(2026, 10, 26, 12).microsecondsSinceEpoch),
      DateTime(2026, 10, 26, 12),
    );
    expect(
      epochToDateTime(DateTime(2026, 10, 26, 12).millisecondsSinceEpoch),
      DateTime(2026, 10, 26, 12),
    );
  });
}
