import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:highlight/highlight.dart' as highlight;
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/swift.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/bash.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../data/pin_store.dart' show PinnedMessage;
import '../../models/chat_message_models.dart';
import '../audio/audio_widgets.dart';
import '../media/media_widgets.dart';

class MessageBubble extends StatelessWidget {
  final UiMessage message;
  final void Function(UiImage image) onDownloadImage;
  final void Function(List<UiImage> images, int index) onOpenMedia;
  final void Function(AudioItem audio) onPlayAudio;
  final bool isPinned;
  final AudioPlayer audioPlayer;
  final AudioNowPlaying? nowPlaying;
  final VoidCallback? onTap;

  const MessageBubble({
    required this.message,
    required this.onDownloadImage,
    required this.onOpenMedia,
    required this.onPlayAudio,
    this.isPinned = false,
    required this.audioPlayer,
    required this.nowPlaying,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = message.text;
    final fromMe = message.fromMe;
    final status = message.status;
    final timeStr = message.timeStr;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final incomingBubble = isDark ? const Color(0xFF2C2C2E) : theme.colorScheme.surfaceContainerHighest;
    final outgoingBubble = isDark ? const Color(0xFF2C2C2E) : theme.colorScheme.primaryContainer;
    final textPrimary = isDark ? const Color(0xFFFFFFFF) : theme.colorScheme.onSurface;
    final textSecondary = isDark ? const Color(0xFF8E8E93) : theme.colorScheme.outline;

    final isVideoOnly = message.images.length == 1 &&
        message.images.first.isVideo &&
        message.images.first.isCircle &&
        text.isEmpty;
    final isStickerOnly = message.images.length == 1 &&
        message.images.first.isSticker &&
        text.isEmpty;
    final hasSticker = message.images.any((e) => e.isSticker);
    final isBigEmoji = text.isNotEmpty &&
        !hasSticker &&
        message.images.isEmpty &&
        _isOnlyEmojis(text);

    final bubbleColor = isVideoOnly || isStickerOnly || isBigEmoji
        ? Colors.transparent
        : (fromMe ? outgoingBubble : incomingBubble);

    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
          padding: isVideoOnly || isStickerOnly
              ? const EdgeInsets.all(2)
              : (hasSticker
                  ? const EdgeInsets.all(4)
                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            color: hasSticker || isBigEmoji ? Colors.transparent : bubbleColor,
            borderRadius: hasSticker || isBigEmoji
                ? null
                : BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(fromMe ? 18 : 4),
                    bottomRight: Radius.circular(fromMe ? 4 : 18),
                  ),
          ),
          child: Column(
            crossAxisAlignment:
                fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (message.fileName != null && message.audio == null) ...[
                FileAttachment(
                  fileName: message.fileName!,
                  fileSize: message.fileSize,
                  filePath: message.filePath,
                  fromMe: fromMe,
                ),
                if (text.isNotEmpty) const SizedBox(height: 6),
              ],
              if (message.audio != null) ...[
                AudioBubble(
                  audio: message.audio!,
                  fromMe: fromMe,
                  onPlay: () => onPlayAudio(message.audio!),
                  audioPlayer: audioPlayer,
                  nowPlaying: nowPlaying,
                ),
                const SizedBox(height: 6),
              ],
              if (message.images.isNotEmpty) ...[
                if (isStickerOnly)
                  StickerView(image: message.images.first)
                else
                  MediaGrid(
                    images: message.images,
                    fromMe: message.fromMe,
                    onOpen: (i) => onOpenMedia(message.images, i),
                    onDownload: (i) => onDownloadImage(message.images[i]),
                  ),
                if (text.isNotEmpty) const SizedBox(height: 6),
              ],
              if (text.isNotEmpty)
                isBigEmoji
                    ? Text(
                        text,
                        style: const TextStyle(fontSize: 48, height: 1.1),
                      )
                    : MarkdownTextWidget(
                        text: text,
                        textColor: textPrimary,
                      ),
              if (!isBigEmoji) const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPinned) ...[
                    Icon(
                      Icons.push_pin,
                      size: 10,
                      color: textSecondary,
                    ),
                    const SizedBox(width: 2),
                  ],
                  if (timeStr.isNotEmpty)
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: textSecondary,
                      ),
                    ),
                  if (status.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Icon(
                      status == '✓✓' ? Icons.done_all : Icons.done,
                      size: 14,
                      color: textSecondary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isOnlyEmojis(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final graphemes = trimmed.split('');
    final emojiOnly = graphemes.every((char) {
      final code = char.codeUnitAt(0);
      return (code >= 0x1F600 && code <= 0x1F64F) ||
          (code >= 0x1F300 && code <= 0x1F5FF) ||
          (code >= 0x1F680 && code <= 0x1F6FF) ||
          (code >= 0x1F900 && code <= 0x1F9FF) ||
          (code >= 0x2600 && code <= 0x26FF) ||
          (code >= 0x2700 && code <= 0x27BF);
    });

    return emojiOnly && graphemes.length <= 3;
  }
}

class MarkdownTextWidget extends StatelessWidget {
  final String text;
  final Color textColor;

  const MarkdownTextWidget({required this.text, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeBg =
        theme.brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);

    final langs = {
      'dart': dart,
      'python': python,
      'py': python,
      'javascript': javascript,
      'js': javascript,
      'typescript': typescript,
      'ts': typescript,
      'go': go,
      'java': java,
      'kotlin': kotlin,
      'swift': swift,
      'rust': rust,
      'cpp': cpp,
      'c++': cpp,
      'c': cpp,
      'bash': bash,
      'sh': bash,
      'shell': bash,
    };
    for (final entry in langs.entries) {
      highlight.highlight.registerLanguage(entry.key, entry.value);
    }

    return SelectionArea(
      child: MarkdownBody(
        data: text,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(color: textColor, height: 1.25),
          code: TextStyle(
            backgroundColor: codeBg,
            color: theme.colorScheme.onSurface,
            fontFamily: 'monospace',
            fontSize: theme.textTheme.bodyMedium?.fontSize,
          ),
          blockquote: TextStyle(
            color: textColor.withOpacity(0.7),
            fontStyle: FontStyle.italic,
          ),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: theme.colorScheme.outline, width: 3),
            ),
          ),
        ),
        builders: {
          'code': CodeBlockBuilder(codeBg, textColor, Theme.of(context)),
        },
      ),
    );
  }
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  final Color codeBg;
  final Color textColor;
  final ThemeData theme;

  CodeBlockBuilder(this.codeBg, this.textColor, this.theme);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final codeText = element.textContent;
    if (codeText.isEmpty) return null;

    String? language;
    final classes = element.attributes['class'];
    if (classes != null) {
      final match = RegExp(r'language-(\w+)').firstMatch(classes);
      language = match?.group(1);
    }

    Widget codeWidget;
    if (language != null) {
      try {
        final result = highlight.highlight.parse(codeText.trim(), language: language);
        codeWidget = HighlightedCodeBlock(
          text: codeText.trim(),
          language: language,
          textColor: textColor,
          codeBg: codeBg,
        );
      } catch (_) {
        codeWidget = SimpleCodeBlock(
          text: codeText.trim(),
          textColor: textColor,
          codeBg: codeBg,
        );
      }
    } else {
      codeWidget = SimpleCodeBlock(
        text: codeText.trim(),
        textColor: textColor,
        codeBg: codeBg,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: codeWidget,
    );
  }
}

class HighlightedCodeBlock extends StatelessWidget {
  final String text;
  final String language;
  final Color textColor;
  final Color codeBg;

  const HighlightedCodeBlock({
    required this.text,
    required this.language,
    required this.textColor,
    required this.codeBg,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = highlight.highlight.parse(text, language: language);
    final spans = _buildSpans(result?.nodes ?? [], theme);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText.rich(
        TextSpan(children: spans, style: const TextStyle(fontFamily: 'monospace')),
      ),
    );
  }

  List<TextSpan> _buildSpans(List<highlight.Node> nodes, ThemeData theme) {
    final spans = <TextSpan>[];
    final colorMap = _getCodeColors(theme: theme);
    for (final node in nodes) {
      if (node.value != null) {
        spans.add(TextSpan(
          text: node.value,
          style: TextStyle(
            color: node.className != null
                ? (colorMap[node.className] ?? textColor)
                : textColor,
          ),
        ));
      } else if (node.children != null) {
        spans.addAll(_buildSpans(node.children!, theme));
      }
    }
    return spans;
  }

  Map<String, Color> _getCodeColors({required ThemeData theme}) {
    return {
      'keyword': theme.colorScheme.primary,
      'string': const Color(0xFF2E7D32),
      'number': const Color(0xFF1565C0),
      'comment': theme.colorScheme.outline,
      'function': const Color(0xFF6A1B9A),
      'class': const Color(0xFFE65100),
      'built_in': theme.colorScheme.secondary,
      'type': const Color(0xFF00838F),
    };
  }
}

class SimpleCodeBlock extends StatelessWidget {
  final String text;
  final Color textColor;
  final Color codeBg;

  const SimpleCodeBlock({
    required this.text,
    required this.textColor,
    required this.codeBg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          color: textColor,
          fontSize: 13,
        ),
      ),
    );
  }
}

class SystemBubble extends StatelessWidget {
  final String text;

  const SystemBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1C1C1E).withOpacity(0.8)
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? const Color(0xFF8E8E93) : theme.colorScheme.outline,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class DateDivider extends StatelessWidget {
  final DateTime date;

  const DateDivider({required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);
    final yesterday = today.subtract(const Duration(days: 1));

    String label;
    if (dateDay == today) {
      label = 'Сегодня';
    } else if (dateDay == yesterday) {
      label = 'Вчера';
    } else {
      label = DateFormat('d MMMM', 'ru').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1C1C1E).withOpacity(0.85)
                : theme.colorScheme.surfaceContainerHighest.withOpacity(0.7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFFAEAEB2) : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class FileAttachment extends StatelessWidget {
  final String fileName;
  final int? fileSize;
  final String? filePath;
  final bool fromMe;

  const FileAttachment({
    required this.fileName,
    this.fileSize,
    this.filePath,
    required this.fromMe,
  });

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _fileIcon() {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.zip') || lower.endsWith('.sxpz') || lower.endsWith('.rar') || lower.endsWith('.7z') || lower.endsWith('.tar') || lower.endsWith('.gz')) return Icons.folder_zip;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return Icons.table_chart;
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return Icons.slideshow;
    if (lower.endsWith('.txt')) return Icons.text_snippet;
    if (lower.endsWith('.apk')) return Icons.android;
    if (lower.endsWith('.mp3') || lower.endsWith('.ogg') || lower.endsWith('.wav') || lower.endsWith('.flac') || lower.endsWith('.aac') || lower.endsWith('.m4a')) return Icons.audiotrack;
    if (lower.endsWith('.mp4') || lower.endsWith('.mkv') || lower.endsWith('.avi') || lower.endsWith('.mov') || lower.endsWith('.webm')) return Icons.movie;
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.gif') || lower.endsWith('.webp') || lower.endsWith('.svg') || lower.endsWith('.bmp')) return Icons.image;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconColor = fromMe
        ? (isDark ? const Color(0xFFFFFFFF) : theme.colorScheme.onPrimaryContainer)
        : (isDark ? const Color(0xFFFFFFFF) : theme.colorScheme.onSurface);
    final fileIconColor = isDark ? const Color(0xFF0A84FF) : theme.colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF2C2C2E).withOpacity(0.6)
            : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? const Color(0xFF38383A).withOpacity(0.4)
              : theme.colorScheme.outline.withOpacity(0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF2C2C2E)
                  : theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_fileIcon(), size: 24, color: fileIconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: iconColor,
                  ),
                ),
                if (fileSize != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatSize(fileSize!),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF8E8E93) : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (filePath != null) ...[
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 20),
              onPressed: () async {
                final uri = Uri.file(filePath!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
              splashRadius: 20,
            ),
          ],
        ],
      ),
    );
  }
}

class PinnedBar extends StatefulWidget {
  final List<PinnedMessage> pinned;
  final void Function(PinnedMessage) onPinTap;
  final void Function(PinnedMessage) onUnpin;

  const PinnedBar({
    required this.pinned,
    required this.onPinTap,
    required this.onUnpin,
  });

  @override
  State<PinnedBar> createState() => _PinnedBarState();
}

class _PinnedBarState extends State<PinnedBar> {
  late PageController _pageCtrl;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void didUpdateWidget(PinnedBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pinned.length != oldWidget.pinned.length) {
      if (_currentPage >= widget.pinned.length) {
        _currentPage = widget.pinned.isEmpty ? 0 : widget.pinned.length - 1;
        _pageCtrl.jumpToPage(_currentPage);
      }
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pins = widget.pinned;
    if (pins.isEmpty) return const SizedBox.shrink();

    final pm = pins[_currentPage];
    final textColor = isDark ? const Color(0xFF8E8E93) : theme.colorScheme.outline;
    final lineColor = isDark ? const Color(0xFF636366) : theme.colorScheme.outline;

    return GestureDetector(
      onTap: () => widget.onPinTap(pm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1C1C1E)
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? const Color(0xFF38383A).withOpacity(0.5)
                  : theme.colorScheme.outline.withOpacity(0.15),
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 32,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: lineColor,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.push_pin, size: 12, color: textColor),
                      const SizedBox(width: 4),
                      Text(
                        'Закреплённое',
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pm.text.isNotEmpty
                        ? (pm.text.length > 80 ? '${pm.text.substring(0, 80)}…' : pm.text)
                        : '📷 ${pm.timeStr}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? const Color(0xFFAEAEB2) : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (pins.length > 1) ...[
              const SizedBox(width: 6),
              Text(
                '${_currentPage + 1}/${pins.length}',
                style: TextStyle(fontSize: 11, color: textColor),
              ),
              const SizedBox(width: 6),
            ],
            GestureDetector(
              onTap: () => widget.onUnpin(pm),
              child: Icon(Icons.close, size: 18, color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}
