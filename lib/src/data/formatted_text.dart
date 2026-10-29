/// Rich text spans as the SimpleX core formats them (`Simplex.Chat.Markdown`).
///
/// The core parses every message text with `parseMaybeMarkdownList` and sends
/// the result in `ChatItem.formattedText`, the same payload the official
/// clients render (`Markdown.hs`, `Messages.hs:1511`). The UI only maps these
/// spans to Telegram's text styles; it never re-parses markdown itself.
enum SpanFormat {
  bold,
  italic,
  strikeThrough,
  snippet,
  secret,
  small,
  colored,
  uri,
  hyperLink,
  simplexLink,
  simplexName,
  command,
  mention,
  email,
  phone,
  unknown,
}

class MessageSpan {
  const MessageSpan({
    required this.text,
    this.format,
    this.colorName,
    this.linkUri,
    this.showText,
    this.commandStr,
  });

  /// Text exactly as the core keeps it. For [SpanFormat.hyperLink] this is
  /// the original `[text](url)` source, so [displayText] unwraps it.
  final String text;
  final SpanFormat? format;

  /// `FormatColor` name for [SpanFormat.colored].
  final String? colorName;

  /// Target of a hyperlink (`Format.hyperLink.linkUri`).
  final String? linkUri;
  final String? showText;

  /// Bare command name without the leading slash (`Format.command`).
  final String? commandStr;

  bool get isSecret => format == SpanFormat.secret;

  bool get isHttpLink =>
      format == SpanFormat.hyperLink &&
      linkUri != null &&
      (linkUri!.startsWith('http://') || linkUri!.startsWith('https://'));

  String get displayText {
    if (format == SpanFormat.hyperLink ||
        format == SpanFormat.simplexLink) {
      return showText ?? linkUri ?? text;
    }
    return text;
  }
}

SpanFormat? _formatOf(Object? raw) => switch (raw) {
  'bold' => SpanFormat.bold,
  'italic' => SpanFormat.italic,
  'strikeThrough' => SpanFormat.strikeThrough,
  'snippet' => SpanFormat.snippet,
  'secret' => SpanFormat.secret,
  'small' => SpanFormat.small,
  'colored' => SpanFormat.colored,
  'uri' => SpanFormat.uri,
  'hyperLink' => SpanFormat.hyperLink,
  'simplexLink' => SpanFormat.simplexLink,
  'simplexName' => SpanFormat.simplexName,
  'command' => SpanFormat.command,
  'mention' => SpanFormat.mention,
  'email' => SpanFormat.email,
  'phone' => SpanFormat.phone,
  'unknown' => SpanFormat.unknown,
  _ => null,
};

/// Turns `ChatItem.formattedText` into spans; null means plain text, which is
/// also how the core signals "nothing to format".
List<MessageSpan>? parseFormattedText(Object? raw) {
  if (raw is! List || raw.isEmpty) return null;
  final spans = <MessageSpan>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final text = entry['text'];
    if (text is! String || text.isEmpty) continue;
    final format = entry['format'];
    if (format is! Map) {
      spans.add(MessageSpan(text: text));
      continue;
    }
    final type = _formatOf(format['type']);
    spans.add(
      MessageSpan(
        text: text,
        format: type,
        colorName: format['color'] as String?,
        linkUri: format['linkUri'] as String?,
        showText: format['showText'] as String?,
        commandStr: format['commandStr'] as String?,
      ),
    );
  }
  return spans.isEmpty ? null : spans;
}

/// The text the bubble paints, i.e. spans joined with hyperlink labels
/// unwrapped (the core keeps the `[text](uri)` source in `text`).
String spansDisplayText(List<MessageSpan> spans) =>
    spans.map((span) => span.displayText).join();
