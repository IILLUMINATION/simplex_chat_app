import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/formatted_text.dart';
import '../../design/app_palette.dart';
import '../../design/app_theme.dart';

/// Paints the spans the core already parsed (`ChatItem.formattedText`) with
/// Telegram's text styles: bold/italic/strike, monospace snippets, colored
/// runs, spoilers that stay covered until tapped, and clickable web/email/
/// phone links. Telegram has no markdown parser of its own in the chat view —
/// it paints entities the same way (`history_view_message.cpp` → text
/// entities). Plain text is drawn untouched.
class MessageRichText extends StatefulWidget {
  const MessageRichText({
    super.key,
    required this.spans,
    required this.text,
    required this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.interactive = true,
    this.onCommand,
  });

  /// Rows from `ChatItem.formattedText`; null paints [text] as-is.
  final List<MessageSpan>? spans;

  /// Text to paint when [spans] is null.
  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow overflow;

  /// Quotes are previews: their spoilers stay covered and links do not open.
  final bool interactive;

  /// Telegram inserts a tapped bot command into the composer instead of
  /// running it (`MessageField::insertBotCommand`).
  final void Function(String command)? onCommand;

  @override
  State<MessageRichText> createState() => _MessageRichTextState();
}

class _MessageRichTextState extends State<MessageRichText> {
  final Set<int> _revealed = <int>{};
  final Map<int, TapGestureRecognizer> _recognizers = {};

  @override
  void didUpdateWidget(covariant MessageRichText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_signature(widget.spans) != _signature(oldWidget.spans)) {
      _revealed.clear();
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  static String _signature(List<MessageSpan>? spans) =>
      spans?.map((span) => '${span.format?.name}:${span.text}').join('\u0000') ??
      '';

  TapGestureRecognizer _recognizer(int index, VoidCallback onTap) {
    final recognizer = _recognizers.putIfAbsent(index, TapGestureRecognizer.new);
    recognizer.onTap = onTap;
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    final spans = widget.spans;
    if (spans == null || spans.isEmpty) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }
    final palette = context.appTheme.palette;
    final children = <InlineSpan>[];
    for (var index = 0; index < spans.length; index++) {
      children.add(_paint(spans[index], index, palette));
    }
    return Text.rich(
      TextSpan(style: widget.style, children: children),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }

  InlineSpan _paint(MessageSpan span, int index, AppPalette palette) {
    final base = widget.style;
    final format = span.format;
    final text = span.displayText;
    switch (format) {
      case null:
        return TextSpan(text: text);
      case SpanFormat.bold:
        return TextSpan(
          text: text,
          style: base.copyWith(fontWeight: FontWeight.bold),
        );
      case SpanFormat.italic:
        return TextSpan(
          text: text,
          style: base.copyWith(fontStyle: FontStyle.italic),
        );
      case SpanFormat.strikeThrough:
        return TextSpan(
          text: text,
          style: base.copyWith(decoration: TextDecoration.lineThrough),
        );
      case SpanFormat.snippet:
        return TextSpan(
          text: text,
          style: base.copyWith(fontFamily: 'monospace'),
        );
      case SpanFormat.small:
        return TextSpan(
          text: text,
          style: base.copyWith(
            fontSize: (base.fontSize ?? 14) * 0.85,
            color: palette.textSecondary,
          ),
        );
      case SpanFormat.colored:
        return TextSpan(
          text: text,
          style: base.copyWith(
            color: _namedColor(span.colorName, base.color ?? palette.text),
          ),
        );
      case SpanFormat.secret:
        return _secret(span, index, base);
      case SpanFormat.mention:
        return TextSpan(
          text: text,
          style: base.copyWith(fontWeight: FontWeight.w500),
        );
      case SpanFormat.command:
        return TextSpan(
          text: text,
          style: base.copyWith(
            color: palette.link,
            fontFamily: 'monospace',
          ),
          recognizer: !widget.interactive || widget.onCommand == null
              ? null
              : _recognizer(
                  index,
                  () => widget.onCommand!('/${span.commandStr ?? text}'),
                ),
        );
      case SpanFormat.uri:
        final link = text.startsWith('http://') || text.startsWith('https://')
            ? text
            : 'https://$text';
        return TextSpan(
          text: text,
          style: _linkStyle(base, palette),
          recognizer: !widget.interactive
              ? null
              : _recognizer(index, () => _openUri(link)),
        );
      case SpanFormat.hyperLink:
        final link = span.linkUri;
        return TextSpan(
          text: text,
          style: _linkStyle(base, palette),
          recognizer: link == null || !widget.interactive
              ? null
              : _recognizer(index, () => _openUri(link)),
        );
      case SpanFormat.email:
        return TextSpan(
          text: text,
          style: _linkStyle(base, palette),
          recognizer: !widget.interactive
              ? null
              : _recognizer(index, () => _openUri('mailto:$text')),
        );
      case SpanFormat.phone:
        return TextSpan(
          text: text,
          style: _linkStyle(base, palette),
          recognizer: !widget.interactive
              ? null
              : _recognizer(index, () => _openUri('tel:$text')),
        );
      case SpanFormat.simplexLink:
      case SpanFormat.simplexName:
        // Official clients only open these through their verified-address
        // flow; the bubble keeps the link styling without a tap target.
        return TextSpan(text: text, style: _linkStyle(base, palette));
      case SpanFormat.unknown:
        return TextSpan(text: text);
    }
  }

  InlineSpan _secret(MessageSpan span, int index, TextStyle base) {
    if (_revealed.contains(index)) {
      return TextSpan(text: span.text, style: base);
    }
    return TextSpan(
      text: span.text,
      style: base.copyWith(
        color: Colors.transparent,
        // `SecretColor` in the official theme is a translucent grey that reads
        // on both outgoing and incoming bubbles.
        backgroundColor: const Color(0x40808080),
      ),
      recognizer: !widget.interactive
          ? null
          : _recognizer(index, () {
              setState(() {
                if (!_revealed.add(index)) _revealed.remove(index);
              });
            }),
    );
  }

  TextStyle _linkStyle(TextStyle base, AppPalette palette) => base.copyWith(
    color: palette.link,
    decoration: TextDecoration.underline,
    decorationColor: palette.link,
  );

  Future<void> _openUri(String uri) async {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return;
    try {
      await launchUrl(parsed, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No handler (or no plugin in tests); Telegram shows no error either.
    }
  }
}

/// The eight `FormatColor` values the core sends. Black and white fall back to
/// the bubble text colour, exactly like the official clients.
Color _namedColor(String? name, Color fallback) => switch (name) {
  'red' => const Color(0xFFE53935),
  'green' => const Color(0xFF4DDA67),
  'blue' => const Color(0xFF0088FF),
  'yellow' => const Color(0xFFFFC107),
  'cyan' => const Color(0xFF00BCD4),
  'magenta' => const Color(0xFFE91E63),
  _ => fallback,
};
