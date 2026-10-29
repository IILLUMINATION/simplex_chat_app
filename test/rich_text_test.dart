import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/formatted_text.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/models.dart';
import 'package:tanglex_chat/src/shell/widgets/message_rich_text.dart';

import 'support/test_fonts.dart';

AppTheme _theme(Brightness brightness) =>
    buildAppTheme(const AppThemeSettings(fontFamily: 'Roboto'), brightness);

final _now = DateTime(2026, 10, 29, 12, 0);

Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  final theme = _theme(brightness);
  return AppThemeScope(
    theme: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.toMaterial(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// The leaf spans the widget actually paints, in order.
List<TextSpan> _painted(WidgetTester tester) {
  final rich = tester.widget<RichText>(
    find.descendant(
      of: find.byType(MessageRichText),
      matching: find.byType(RichText),
    ),
  );
  final leaves = <TextSpan>[];
  void visit(InlineSpan span) {
    if (span is! TextSpan) return;
    if (span.text != null && span.text!.isNotEmpty) leaves.add(span);
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child);
    }
  }

  visit(rich.text);
  return leaves;
}

Widget _rich(
  List<MessageSpan>? spans, {
  String? text,
  TextStyle? style,
  void Function(String command)? onCommand,
  bool interactive = true,
}) => MessageRichText(
  spans: spans,
  text: text ?? spansDisplayText(spans ?? const []),
  style: style ?? const TextStyle(fontSize: 14, color: Color(0xFF000000)),
  interactive: interactive,
  onCommand: onCommand,
);

/// Taps the glyphs of `[start, end)` so a span recognizer, not the bubble,
/// receives the pointer.
Future<void> _tapText(WidgetTester tester, int start, int end) async {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.byType(MessageRichText),
      matching: find.byType(RichText),
    ),
  );
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: end),
  );
  final box = boxes.first;
  final local = Offset(
    (box.left + box.right) / 2,
    (box.top + box.bottom) / 2,
  );
  await tester.tapAt(paragraph.localToGlobal(local));
  await tester.pump();
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('null spans paint the plain text untouched', (tester) async {
    await tester.pumpWidget(_host(_rich(null, text: 'plain *text*')));
    expect(find.text('plain *text*'), findsOneWidget);
    final spans = _painted(tester);
    expect(spans, hasLength(1));
    expect(spans.single.text, 'plain *text*');
    expect(spans.single.recognizer, isNull);
    expect(spans.single.style?.color, const Color(0xFF000000));
  });

  testWidgets('core formats map to Telegram text styles', (tester) async {
    await tester.pumpWidget(
      _host(
        _rich(const [
          MessageSpan(text: 'bold', format: SpanFormat.bold),
          MessageSpan(text: 'it', format: SpanFormat.italic),
          MessageSpan(text: 'gone', format: SpanFormat.strikeThrough),
          MessageSpan(text: 'code', format: SpanFormat.snippet),
          MessageSpan(text: 'small', format: SpanFormat.small),
          MessageSpan(
            text: 'red',
            format: SpanFormat.colored,
            colorName: 'red',
          ),
          MessageSpan(text: '@bob', format: SpanFormat.mention),
        ]),
      ),
    );
    final spans = _painted(tester);
    expect(spans, hasLength(7));
    expect(spans[0].style?.fontWeight, FontWeight.bold);
    expect(spans[1].style?.fontStyle, FontStyle.italic);
    expect(spans[2].style?.decoration, TextDecoration.lineThrough);
    expect(spans[3].style?.fontFamily, 'monospace');
    expect(spans[4].style?.fontSize, closeTo(14 * 0.85, 0.01));
    expect(spans[5].style?.color, const Color(0xFFE53935));
    expect(spans[6].style?.fontWeight, FontWeight.w500);
  });

  testWidgets('a spoiler stays covered until tapped', (tester) async {
    await tester.pumpWidget(
      _host(
        _rich(const [
          MessageSpan(text: 'before ', format: null),
          MessageSpan(text: 'secret', format: SpanFormat.secret),
        ]),
      ),
    );
    var spans = _painted(tester);
    expect(spans[1].style?.color, Colors.transparent);
    expect(spans[1].style?.backgroundColor, const Color(0x40808080));
    expect(spans[1].recognizer, isNotNull);

    await _tapText(tester, 7, 13);

    spans = _painted(tester);
    expect(spans[1].style?.color, isNot(Colors.transparent));
    expect(spans[1].style?.backgroundColor, isNull);
  });

  testWidgets('quote previews keep spoilers covered and links inert', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _rich(
          const [
            MessageSpan(text: 'secret', format: SpanFormat.secret),
            MessageSpan(
              text: '[label](https://example.com)',
              format: SpanFormat.hyperLink,
              linkUri: 'https://example.com',
              showText: 'label',
            ),
          ],
          interactive: false,
        ),
      ),
    );
    final spans = _painted(tester);
    expect(spans[1].text, 'label');
    expect(spans[1].recognizer, isNull);
    expect(spans[1].style?.decoration, TextDecoration.underline);
    // A preview never reveals: the secret keeps its cover and no recognizer.
    expect(spans[0].style?.color, Colors.transparent);
    expect(spans[0].recognizer, isNull);
  });

  testWidgets('a tapped bot command goes to the composer callback', (
    tester,
  ) async {
    String? tapped;
    await tester.pumpWidget(
      _host(
        _rich(
          const [
            MessageSpan(
              text: '/help',
              format: SpanFormat.command,
              commandStr: 'help',
            ),
          ],
          onCommand: (command) => tapped = command,
        ),
      ),
    );
    await _tapText(tester, 0, 5);
    expect(tapped, '/help');
  });

  testWidgets('tapping a command in a bubble fills the composer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ConversationPanel(
          chat: const ChatSummary(
            id: '@1',
            name: 'Alice',
            preview: 'Commands',
            time: '12:04',
          ),
          messages: [
            MessageItem(
              text: 'tap /help to see the list',
              time: '12:04',
              timestamp: _now,
              outgoing: false,
              sender: 'Alice',
              itemId: 11,
              spans: const [
                MessageSpan(text: 'tap '),
                MessageSpan(
                  text: '/help',
                  format: SpanFormat.command,
                  commandStr: 'help',
                ),
                MessageSpan(text: ' to see the list'),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapText(tester, 4, 9);

    final compose = tester.widget<TextField>(find.byType(TextField));
    expect(compose.controller?.text, '/help ');
    expect(compose.focusNode?.hasFocus, isTrue);
  });
}
