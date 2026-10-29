import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/formatted_text.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/models.dart';

import '../support/test_fonts.dart';

AppTheme _theme(Brightness brightness) =>
    buildAppTheme(const AppThemeSettings(fontFamily: 'Roboto'), brightness);

final _now = DateTime(2026, 10, 29, 12, 0);

MessageItem _text({
  required List<MessageSpan> spans,
  required String time,
  required bool outgoing,
  String? sender = 'Alice',
  MessageReply? reply,
}) => MessageItem(
  text: spansDisplayText(spans),
  spans: spans,
  time: time,
  timestamp: _now,
  outgoing: outgoing,
  sender: sender,
  itemId: time.hashCode,
  reply: reply,
);

final _messages = <MessageItem>[
  const MessageItem(text: 'Today', time: '', isDateSeparator: true),
  _text(
    time: '12:01',
    outgoing: false,
    spans: const [
      MessageSpan(text: 'Ship '),
      MessageSpan(text: 'today', format: SpanFormat.bold),
      MessageSpan(text: ', not '),
      MessageSpan(text: 'tomorrow', format: SpanFormat.italic),
      MessageSpan(text: '. '),
      MessageSpan(text: 'Obsolete plan.', format: SpanFormat.strikeThrough),
    ],
  ),
  _text(
    time: '12:02',
    outgoing: false,
    spans: const [
      MessageSpan(text: 'Run '),
      MessageSpan(text: 'git push --force', format: SpanFormat.snippet),
      MessageSpan(text: ' only in '),
      MessageSpan(
        text: 'emergencies',
        format: SpanFormat.colored,
        colorName: 'red',
      ),
      MessageSpan(
        text: ' (read the manual first)',
        format: SpanFormat.small,
      ),
    ],
  ),
  _text(
    time: '12:03',
    outgoing: true,
    sender: null,
    spans: const [
      MessageSpan(text: 'Ping '),
      MessageSpan(text: '@alice', format: SpanFormat.mention),
      MessageSpan(text: ': see '),
      MessageSpan(
        text: '[the docs](https://example.com/docs)',
        format: SpanFormat.hyperLink,
        linkUri: 'https://example.com/docs',
        showText: 'the docs',
      ),
      MessageSpan(text: ' or '),
      MessageSpan(text: 'example.org/faq', format: SpanFormat.uri),
    ],
  ),
  _text(
    time: '12:04',
    outgoing: true,
    sender: null,
    reply: const MessageReply(
      author: 'Alice',
      text: '[the docs](https://example.com/docs)',
      spans: [
        MessageSpan(text: 'read '),
        MessageSpan(
          text: '[the docs](https://example.com/docs)',
          format: SpanFormat.hyperLink,
          linkUri: 'https://example.com/docs',
          showText: 'the docs',
        ),
      ],
    ),
    spans: const [
      MessageSpan(text: 'Done, hidden answer: '),
      MessageSpan(text: 'the plot twist', format: SpanFormat.secret),
      MessageSpan(text: '. Tap '),
      MessageSpan(
        text: '/help',
        format: SpanFormat.command,
        commandStr: 'help',
      ),
    ],
  ),
];

Widget _harness(Brightness brightness) {
  final theme = _theme(brightness);
  return AppThemeScope(
    theme: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.toMaterial(),
      home: Scaffold(
        body: ConversationPanel(
          chat: const ChatSummary(
            id: '@1',
            name: 'Alice',
            preview: 'Markdown',
            time: '12:04',
          ),
          messages: _messages,
        ),
      ),
    ),
  );
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('desktop markdown bubbles light', (tester) async {
    await _setSize(tester, const Size(900, 900));
    await tester.pumpWidget(_harness(Brightness.light));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ConversationPanel),
      matchesGoldenFile('goldens/markdown_desktop_light.png'),
    );
  });

  testWidgets('phone markdown bubbles dark', (tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(_harness(Brightness.dark));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ConversationPanel),
      matchesGoldenFile('goldens/markdown_phone_dark.png'),
    );
  });
}
