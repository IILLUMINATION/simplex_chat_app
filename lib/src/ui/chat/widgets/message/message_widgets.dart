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
import 'package:open_filex/open_filex.dart';
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
  final void Function(AudioItem audio) onDownloadAudio;
  final void Function(UiMessage message) onDownloadFile;
  final bool isPinned;
  final AudioPlayer audioPlayer;
  final AudioNowPlaying? nowPlaying;
  final void Function(LongPressStartDetails, BuildContext)? onLongPress;
  final VoidCallback? onSwipeReply;
  final VoidCallback? onQuotedTap;

  const MessageBubble({
    required this.message,
    required this.onDownloadImage,
    required this.onOpenMedia,
    required this.onPlayAudio,
    required this.onDownloadAudio,
    required this.onDownloadFile,
    this.isPinned = false,
    required this.audioPlayer,
    required this.nowPlaying,
    this.onLongPress,
    this.onSwipeReply,
    this.onQuotedTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = message.text;
    final fromMe = message.fromMe;
    final status = message.status;
    final timeStr = message.timeStr;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final incomingBubble = const Color(0xFF191919);
    final outgoingBubble = const Color(0xFF191919);
    final textPrimary = const Color(0xFFE8E8E8);
    final textSecondary = const Color(0xFF808080);

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
      child: SwipeReplyWrapper(
        enabled: onSwipeReply != null,
        fromMe: fromMe,
        onReply: onSwipeReply,
        onLongPressStart: onLongPress == null ? null : (d) => onLongPress!(d, context),
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
            boxShadow: hasSticker || isBigEmoji
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
                  fileId: message.fileId,
                  fileStatusType: message.fileStatusType,
                  transferProgress: message.transferProgress,
                  transferTotal: message.transferTotal,
                  fromMe: fromMe,
                  onDownload: () => onDownloadFile(message),
                ),
                if (text.isNotEmpty) const SizedBox(height: 6),
              ],
              if (message.audio != null) ...[
                AudioBubble(
                  audio: message.audio!,
                  fromMe: fromMe,
                  onPlay: () => onPlayAudio(message.audio!),
                  onDownload: () => onDownloadAudio(message.audio!),
                  audioPlayer: audioPlayer,
                  nowPlaying: nowPlaying,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
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
              if (message.quoted != null) ...[
                GestureDetector(
                  onTap: message.quoted!.itemId != null ? onQuotedTap : null,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF303030),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF3A3A3A),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 28,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF5A9CF5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                message.quoted!.senderName.isNotEmpty
                                    ? message.quoted!.senderName
                                    : (fromMe ? 'Вы' : ''),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF5A9CF5),
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                message.quoted!.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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

class SwipeReplyWrapper extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final bool fromMe;
  final VoidCallback? onReply;
  final void Function(LongPressStartDetails)? onLongPressStart;

  const SwipeReplyWrapper({
    required this.child,
    required this.enabled,
    required this.fromMe,
    required this.onReply,
    this.onLongPressStart,
  });

  @override
  State<SwipeReplyWrapper> createState() => _SwipeReplyWrapperState();
}

class _SwipeReplyWrapperState extends State<SwipeReplyWrapper> with SingleTickerProviderStateMixin {
  static const double _maxOffset = -64;
  static const double _triggerOffset = -48;
  double _offset = 0;
  bool _triggered = false;
  late final AnimationController _controller;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  }

  void _animateBack() {
    final begin = _offset;
    _offset = 0;
    _controller.reset();
    _anim = Tween<double>(begin: begin, end: 0).chain(CurveTween(curve: Curves.easeOut)).animate(_controller);
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final offset = _controller.isAnimating ? _anim.value : _offset;
        final showReply = offset.abs() > 8;
        return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: widget.onLongPressStart,
      onHorizontalDragUpdate: widget.enabled
          ? (d) {
              final delta = d.delta.dx;
              if (delta >= 0 && _offset >= 0) return;
              final next = (_offset + delta).clamp(_maxOffset, 0.0);
              if (next <= _triggerOffset && !_triggered) {
                _triggered = true;
                HapticFeedback.selectionClick();
              }
              setState(() {
                _offset = next;
              });
            }
          : null,
      onHorizontalDragEnd: widget.enabled
          ? (_) {
              final shouldReply = _offset <= _triggerOffset;
              _animateBack();
              if (shouldReply) widget.onReply?.call();
              _triggered = false;
            }
          : null,
      onHorizontalDragCancel: widget.enabled
          ? () {
              _animateBack();
              _triggered = false;
            }
          : null,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          if (showReply)
            Positioned(
              right: 6,
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: Color(0xFF2A2A2A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.reply, size: 14, color: Color(0xFF8AB4F8)),
              ),
            ),
          Transform.translate(
            offset: Offset(offset, 0),
            child: widget.child,
          ),
        ],
      ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class MarkdownTextWidget extends StatelessWidget {
  final String text;
  final Color textColor;

  const MarkdownTextWidget({required this.text, required this.textColor});

  static bool _langsRegistered = false;
  static void _registerLanguages() {
    if (_langsRegistered) return;
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
    _langsRegistered = true;
  }

  @override
  Widget build(BuildContext context) {
    _registerLanguages();
    final theme = Theme.of(context);
    final codeBg =
        theme.brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      color: textColor,
      height: 1.35,
      fontSize: 14.5,
    );

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

    return MarkdownBody(
      data: text,
      selectable: true,
      softLineBreak: true,
      onTapLink: (text, href, title) async {
        if (href == null) return;
        final uri = Uri.tryParse(href);
        if (uri == null) return;
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      styleSheet: MarkdownStyleSheet(
        p: baseStyle,
        h1: baseStyle?.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
        h2: baseStyle?.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
        h3: baseStyle?.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
        strong: baseStyle?.copyWith(fontWeight: FontWeight.w700),
        em: baseStyle?.copyWith(fontStyle: FontStyle.italic),
        code: TextStyle(
          backgroundColor: codeBg,
          color: theme.colorScheme.onSurface,
          fontFamily: 'monospace',
          fontSize: theme.textTheme.bodyMedium?.fontSize,
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: codeBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        blockquote: baseStyle?.copyWith(color: textColor.withOpacity(0.75)),
        blockquoteDecoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          border: Border(left: BorderSide(color: theme.colorScheme.outline, width: 3)),
        ),
        listBullet: baseStyle,
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colorScheme.outline)),
        ),
        a: baseStyle?.copyWith(color: const Color(0xFF8AB4F8)),
      ),
      builders: {
        'code': CodeBlockBuilder(codeBg, textColor, Theme.of(context)),
      },
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
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C).withOpacity(0.8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF808080),
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
            color: const Color(0xFF1C1C1C).withOpacity(0.85),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFB0B0B0),
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
  final int? fileId;
  final String? fileStatusType;
  final int? transferProgress;
  final int? transferTotal;
  final bool fromMe;
  final VoidCallback? onDownload;

  const FileAttachment({
    required this.fileName,
    this.fileSize,
    this.filePath,
    this.fileId,
    this.fileStatusType,
    this.transferProgress,
    this.transferTotal,
    required this.fromMe,
    this.onDownload,
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
    final textColor = const Color(0xFFE8E8E8);
    final sizeColor = const Color(0xFF808080);
    final iconBgColor = const Color(0xFF2A2A2A);
    final fileIconColor = const Color(0xFF8AB4F8);
    final containerBg = const Color(0xFF222222);

    final isIncoming = !fromMe;
    final hasLocal = filePath != null && filePath!.isNotEmpty;
    final awaitingSender = isIncoming &&
        !hasLocal &&
        fileStatusType == 'rcvInvitation' &&
        fileSize == null;
    final needsDownload = isIncoming &&
        !hasLocal &&
        fileId != null &&
        fileStatusType == 'rcvInvitation' &&
        !awaitingSender;
    final isDownloading =
        isIncoming && !hasLocal && (fileStatusType == 'rcvTransfer' || fileStatusType == 'rcvAccepted');
    final showProgress = transferProgress != null && transferTotal != null && transferTotal! > 0;
    final progress = showProgress ? (transferProgress! / transferTotal!).clamp(0.0, 1.0) : null;

    Future<void> openFile() async {
      if (!hasLocal) return;
      try {
        final result = await OpenFilex.open(filePath!);
        if (result.type != ResultType.done && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось открыть файл: ${result.message ?? result.type}')),
          );
        }
      } on MissingPluginException {
        final uri = Uri.file(filePath!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нет приложения для открытия файла')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось открыть файл: $e')),
          );
        }
      }
    }

    return InkWell(
      onTap: hasLocal ? openFile : (needsDownload ? onDownload : null),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 250),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: containerBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF333333),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_fileIcon(), size: 20, color: fileIconColor),
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
                      fontSize: 13,
                      color: textColor,
                      height: 1.2,
                    ),
                  ),
                  if (awaitingSender) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Ожидает отправителя',
                      style: TextStyle(
                        fontSize: 11,
                        color: sizeColor,
                      ),
                    ),
                  ] else if (fileSize != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatSize(fileSize!),
                      style: TextStyle(
                        fontSize: 11,
                        color: sizeColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (awaitingSender)
              const Icon(Icons.hourglass_empty, size: 18, color: Color(0xFF8AB4F8))
            else if (needsDownload)
              IconButton(
                icon: Icon(Icons.download, size: 20, color: fileIconColor),
                onPressed: onDownload,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                splashRadius: 20,
              )
            else if (isDownloading || showProgress)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress,
                  valueColor: AlwaysStoppedAnimation<Color>(fileIconColor),
                ),
              )
            else if (hasLocal)
              IconButton(
                icon: Icon(Icons.open_in_new, size: 18, color: fileIconColor),
                onPressed: openFile,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                splashRadius: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class PinnedBar extends StatefulWidget {
  final List<PinnedMessage> pinned;
  final void Function(PinnedMessage, {void Function()? onComplete}) onPinTap;
  final void Function(PinnedMessage) onUnpin;
  final bool Function(PinnedMessage) isPinVisible;

  const PinnedBar({
    required this.pinned,
    required this.onPinTap,
    required this.onUnpin,
    required this.isPinVisible,
  });

  @override
  State<PinnedBar> createState() => _PinnedBarState();
}

class _PinnedBarState extends State<PinnedBar> {
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(PinnedBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pinned.length != oldWidget.pinned.length) {
      if (_currentPage >= widget.pinned.length) {
        _currentPage = widget.pinned.isEmpty ? 0 : widget.pinned.length - 1;
      }
    }
  }

  void _syncCurrentPage() {
    final pins = widget.pinned;
    if (pins.isEmpty || pins.length <= 1) return;

    // Проверяем, какие пины сейчас видимы
    final visibleIndices = <int>[];
    for (int i = 0; i < pins.length; i++) {
      if (widget.isPinVisible(pins[i])) {
        visibleIndices.add(i);
      }
    }

    // Если текущий _currentPage стал видимым — оставляем его
    final clamped = _currentPage.clamp(0, pins.length - 1);
    if (visibleIndices.contains(clamped)) return;

    // Если _currentPage не виден, но есть видимые — переключиться на последний видимый
    if (visibleIndices.isNotEmpty) {
      final lastVisible = visibleIndices.reduce((a, b) => a > b ? a : b);
      if (lastVisible != _currentPage) {
        // Откладываем setState до следующего фрейма
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _currentPage = lastVisible);
          }
        });
      }
      return;
    }

    // Ни один не виден — ничего не делаем
  }

  void _advanceToNext(List<PinnedMessage> pins) {
    if (pins.isEmpty) return;
    if (pins.length == 1) {
      widget.onPinTap(pins.first);
      return;
    }
    final displayIndex = _selectDisplayIndex(pins);
    final nextIndex = (displayIndex + 1) % pins.length;
    widget.onPinTap(
      pins[nextIndex],
      onComplete: () {
        setState(() => _currentPage = nextIndex);
      },
    );
  }

  int _selectDisplayIndex(List<PinnedMessage> pins) {
    if (pins.isEmpty) return 0;

    // Проверяем, все ли пины видимы
    bool allVisible = true;
    for (int i = 0; i < pins.length; i++) {
      if (!widget.isPinVisible(pins[i])) {
        allVisible = false;
        break;
      }
    }
    if (allVisible) return 0;

    // currentPage виден — не переключаемся
    final clampedCurrent = _currentPage.clamp(0, pins.length - 1);
    if (widget.isPinVisible(pins[clampedCurrent])) {
      return clampedCurrent;
    }

    // Ищем первый невидимый
    for (int i = 0; i < pins.length; i++) {
      final idx = (_currentPage + i) % pins.length;
      if (!widget.isPinVisible(pins[idx])) {
        return idx;
      }
    }

    return 0;
  }

  @override
  Widget build(BuildContext context) {
    _syncCurrentPage();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pins = widget.pinned;
    if (pins.isEmpty) return const SizedBox.shrink();

    final displayIndex = _selectDisplayIndex(pins);
    final pm = pins[displayIndex];
    final textColor = const Color(0xFF808080);
    final lineColor = const Color(0xFF5A9CF5);

    return GestureDetector(
      onTap: () => _advanceToNext(pins),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          border: Border(
            bottom: BorderSide(
              color: const Color(0xFF333333),
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
                      color: const Color(0xFFB0B0B0),
                    ),
                  ),
                ],
              ),
            ),
            if (pins.length > 1) ...[
              const SizedBox(width: 6),
              Text(
                '${displayIndex + 1}/${pins.length}',
                style: TextStyle(fontSize: 11, color: textColor),
              ),
              const SizedBox(width: 6),
            ],
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onUnpin(pm),
              child: Icon(Icons.close, size: 18, color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}
