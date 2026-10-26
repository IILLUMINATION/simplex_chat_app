import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/app_metrics.dart';
import '../design/app_palette.dart';
import '../design/app_theme.dart';
import 'appearance_settings.dart';
import 'models.dart';
import 'widgets/peer_avatar.dart';

class ConversationPanel extends StatefulWidget {
  const ConversationPanel({
    super.key,
    required this.chat,
    required this.messages,
    this.onBack,
    this.onToggleDetails,
    this.onSend,
    this.canSend = true,
    this.sending = false,
    this.loading = false,
    this.searchRequest = 0,
  });

  final ChatSummary chat;
  final List<MessageItem> messages;
  final VoidCallback? onBack;
  final VoidCallback? onToggleDetails;
  final ValueChanged<String>? onSend;
  final bool canSend;
  final bool sending;
  final bool loading;

  /// Incremented externally (details panel) to open message search.
  final int searchRequest;

  @override
  State<ConversationPanel> createState() => _ConversationPanelState();
}

class _ConversationPanelState extends State<ConversationPanel> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searching = false;

  @override
  void didUpdateWidget(covariant ConversationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchRequest != oldWidget.searchRequest) {
      _openSearch();
    }
    if (widget.chat.id != oldWidget.chat.id) {
      _closeSearch();
    }
  }

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _search.clear();
    if (_searching) setState(() => _searching = false);
  }

  String get _query => _search.text.trim().toLowerCase();

  List<MessageItem> _visibleMessages() {
    final query = _query;
    if (!_searching || query.isEmpty) return widget.messages;
    return widget.messages
        .where(
          (m) =>
              !m.isDateSeparator &&
              !m.isSystem &&
              (m.text.toLowerCase().contains(query) ||
                  (m.sender?.toLowerCase().contains(query) ?? false) ||
                  (m.mediaLabel?.toLowerCase().contains(query) ?? false)),
        )
        .toList();
  }

  void _openAppearance() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AppearanceScreenHost()),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final m = theme.metrics;
    final t = theme.typography;
    final visible = _visibleMessages();

    return Column(
      children: [
        Container(
          height: m.topBarHeight,
          color: p.topBarBg,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _searching
              ? Row(
                  children: [
                    _IconButton(
                      icon: Icons.arrow_back,
                      onTap: _closeSearch,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: p.windowBgOver,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Center(
                          child: TextField(
                            controller: _search,
                            focusNode: _searchFocus,
                            onChanged: (_) => setState(() {}),
                            style: t.input.copyWith(color: p.text),
                            cursorColor: p.accent,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Search messages',
                              hintStyle: t.input.copyWith(
                                color: p.searchHint,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_search.text.isNotEmpty)
                      _IconButton(
                        icon: Icons.close,
                        onTap: () {
                          _search.clear();
                          setState(() {});
                        },
                      ),
                  ],
                )
              : Row(
                  children: [
                    if (widget.onBack != null)
                      _IconButton(icon: Icons.arrow_back, onTap: widget.onBack),
                    const SizedBox(width: 4),
                    PeerAvatar(
                      seed: widget.chat.id,
                      title: widget.chat.name,
                      size: m.topBarHeight - 16,
                      imageBytes: widget.chat.avatarBytes,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.chat.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.chatTitle.copyWith(color: p.text),
                          ),
                          Text(
                            widget.chat.subtitle ??
                                (widget.chat.online
                                    ? 'online'
                                    : 'last seen recently'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.listTime.copyWith(
                              color: widget.chat.online
                                  ? p.link
                                  : p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _IconButton(icon: Icons.search, onTap: _openSearch),
                    if (widget.onToggleDetails != null)
                      _IconButton(
                        icon: Icons.info_outline,
                        onTap: widget.onToggleDetails,
                      ),
                    PopupMenuButton<_ChatMenuAction>(
                      tooltip: 'More',
                      onSelected: (action) {
                        switch (action) {
                          case _ChatMenuAction.info:
                            widget.onToggleDetails?.call();
                            break;
                          case _ChatMenuAction.appearance:
                            _openAppearance();
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        if (widget.onToggleDetails != null)
                          const PopupMenuItem(
                            value: _ChatMenuAction.info,
                            child: Text('Chat info'),
                          ),
                        const PopupMenuItem(
                          value: _ChatMenuAction.appearance,
                          child: Text('Appearance'),
                        ),
                      ],
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(
                          Icons.more_vert,
                          size: m.iconSize,
                          color: p.icon,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        Container(height: 1, color: p.divider),
        Expanded(
          child: _MessageList(
            messages: visible,
            loading: widget.loading,
            emptyLabel: _searching && _query.isNotEmpty
                ? 'No results'
                : 'No messages yet',
          ),
        ),
        _ComposeBar(
          onSend: widget.onSend,
          canSend: widget.canSend,
          sending: widget.sending,
        ),
      ],
    );
  }
}

enum _ChatMenuAction { info, appearance }

class _MessageList extends StatefulWidget {
  const _MessageList({
    required this.messages,
    required this.loading,
    required this.emptyLabel,
  });

  final List<MessageItem> messages;
  final bool loading;
  final String emptyLabel;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final _controller = ScrollController();
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.messages.length;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  @override
  void didUpdateWidget(covariant _MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != _lastCount) {
      _lastCount = widget.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
    }
  }

  void _jumpToEnd() {
    if (!mounted || !_controller.hasClients) return;
    _controller.jumpTo(_controller.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final m = theme.metrics;

    if (widget.messages.isEmpty) {
      return Container(
        color: theme.palette.chatWallpaper,
        alignment: Alignment.center,
        child: widget.loading
            ? CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.palette.accent,
              )
            : Text(
                widget.emptyLabel,
                style: theme.typography.listTime.copyWith(
                  color: theme.palette.textSecondary,
                ),
              ),
      );
    }

    return Container(
      color: theme.palette.chatWallpaper,
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
        itemCount: widget.messages.length,
        itemBuilder: (context, index) {
          final message = widget.messages[index];
          if (message.isDateSeparator) {
            return Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
              child: Center(child: _Pill(label: message.text)),
            );
          }
          if (message.isSystem) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Center(child: _Pill(label: message.text)),
            );
          }
          return _MessageRow(message: message, bubbleMargin: m.bubbleMargin);
        },
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      hoverColor: theme.palette.windowBgOver,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          size: theme.metrics.iconSize,
          color: theme.palette.icon,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      decoration: BoxDecoration(
        color: p.datePillBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.typography.service.copyWith(color: p.serviceText),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message, required this.bubbleMargin});

  final MessageItem message;
  final EdgeInsets bubbleMargin;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final m = theme.metrics;

    final bottomGap = message.lastInGroup ? m.messageGroupGap : m.attachedGap;

    return Padding(
      padding: EdgeInsets.only(
        left: bubbleMargin.left,
        right: bubbleMargin.right,
        bottom: bottomGap,
      ),
      child: Align(
        alignment: message.outgoing
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(
              m.bubbleMaxWidth,
              MediaQuery.sizeOf(context).width * 0.78,
            ),
            minWidth: 0,
          ),
          child: _Bubble(
            message: message,
            firstInGroup: message.firstInGroup,
            lastInGroup: message.lastInGroup,
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.firstInGroup,
    required this.lastInGroup,
  });

  final MessageItem message;
  final bool firstInGroup;
  final bool lastInGroup;

  BorderRadius _radius(AppMetrics metrics) {
    final r = Radius.circular(metrics.bubbleRadius);
    final tail = Radius.circular(metrics.bubbleTailRadius);
    if (message.outgoing) {
      return BorderRadius.only(
        topLeft: r,
        topRight: firstInGroup ? r : tail,
        bottomLeft: r,
        bottomRight: lastInGroup ? r : tail,
      );
    }
    return BorderRadius.only(
      topLeft: firstInGroup ? r : tail,
      topRight: r,
      bottomLeft: lastInGroup ? r : tail,
      bottomRight: r,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final m = theme.metrics;
    final t = theme.typography;

    final out = message.outgoing;
    final failed = message.status == MessageStatus.failed;
    final textColor = out ? p.bubbleTextOut : p.bubbleTextIn;
    final metaColor = out ? p.timeOut : p.timeIn;
    final replyColor = out ? p.replyBarOut : p.replyBarIn;

    return Container(
      decoration: BoxDecoration(
        color: failed
            ? Color.alphaBlend(
                const Color(0x33FF3B30),
                out ? p.bubbleOut : p.bubbleIn,
              )
            : (out ? p.bubbleOut : p.bubbleIn),
        borderRadius: _radius(m),
        boxShadow: [
          BoxShadow(
            color: const Color(0x14000000),
            offset: Offset(0, m.bubbleShadowOffset),
            blurRadius: 1,
          ),
        ],
      ),
      padding: m.bubblePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.reply != null) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: replyColor, width: m.replyBarWidth),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.reply!.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.sender.copyWith(color: replyColor),
                  ),
                  Text(
                    message.reply!.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.messageMeta.copyWith(color: textColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
          ],
          if (message.sender != null && firstInGroup && !out) ...[
            Text(message.sender!, style: t.sender.copyWith(color: p.link)),
            const SizedBox(height: 2),
          ],
          if (message.mediaLabel != null) ...[
            _MediaPreview(message: message),
            const SizedBox(height: 4),
            Text(
              message.mediaLabel!,
              style: t.messageMeta.copyWith(color: textColor),
            ),
            const SizedBox(height: 2),
          ],
          if (message.text.isNotEmpty)
            Text(message.text, style: t.message.copyWith(color: textColor)),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.time,
                style: t.messageMeta.copyWith(color: metaColor),
              ),
              if (out) ...[
                const SizedBox(width: 3),
                _StatusIcon(status: message.status),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({required this.message});

  final MessageItem message;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final bytes = message.imageBytes;
    final path = message.imagePath;

    Widget? image;
    if (bytes != null) {
      image = Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(p),
      );
    } else if (path != null && File(path).existsSync()) {
      image = Image.file(
        File(path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(p),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 240,
        height: image == null ? 120 : 150,
        child: image ?? _placeholder(p),
      ),
    );
  }

  Widget _placeholder(AppPalette palette) {
    return ColoredBox(
      color: palette.windowBgOver,
      child: Center(
        child: Icon(Icons.image_outlined, size: 32, color: palette.icon),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final metaColor = p.timeOut;

    final (IconData icon, Color color) = switch (status) {
      MessageStatus.none => (Icons.done, metaColor),
      MessageStatus.sending => (Icons.schedule, metaColor),
      MessageStatus.failed => (Icons.error_outline, const Color(0xFFFF3B30)),
      MessageStatus.sent => (Icons.done, metaColor),
      MessageStatus.delivered => (Icons.done_all, metaColor),
      MessageStatus.read => (Icons.done_all, p.ticksOut),
    };

    return Icon(icon, size: 14, color: color);
  }
}

class _ComposeBar extends StatefulWidget {
  const _ComposeBar({
    required this.onSend,
    required this.canSend,
    required this.sending,
  });

  final ValueChanged<String>? onSend;
  final bool canSend;
  final bool sending;

  @override
  State<_ComposeBar> createState() => _ComposeBarState();
}

class _ComposeBarState extends State<_ComposeBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.canSend) return;
    widget.onSend?.call(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  Future<void> _pickEmoji() async {
    final emoji = await showEmojiPicker(context);
    if (emoji == null || !mounted) return;
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final next = value.text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _focusNode.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    _send();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final m = theme.metrics;
    final t = theme.typography;

    final sendEnabled = _hasText && widget.canSend;

    return Container(
      constraints: BoxConstraints(minHeight: m.composeBarHeight),
      color: p.composeBg,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(width: 6),
          Expanded(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: m.composeBarHeight - 12,
                maxHeight: m.composeFieldMaxHeight,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: p.windowBgOver,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Focus(
                  onKeyEvent: _onKey,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    enabled: widget.canSend,
                    style: t.input.copyWith(color: p.text),
                    cursorColor: p.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: widget.canSend ? 'Message' : 'Not connected',
                      hintStyle: t.input.copyWith(color: p.searchHint),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _IconButton(icon: Icons.emoji_emotions_outlined, onTap: _pickEmoji),
          Padding(
            padding: const EdgeInsets.only(
              left: 4,
              right: 2,
              bottom: 4,
              top: 2,
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: sendEnabled ? _send : null,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: sendEnabled ? p.accent : p.windowBgOver,
                  shape: BoxShape.circle,
                ),
                child: widget.sending
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: p.accent,
                        ),
                      )
                    : Icon(
                        Icons.send,
                        size: 20,
                        color: sendEnabled ? p.onAccent : p.searchHint,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _emojiChoices = <String>[
  '😀', '😄', '😁', '😂', '🤣', '😊', '🙂', '😉', '😍', '😘',
  '😎', '🤔', '😐', '🙄', '😢', '😭', '😡', '🥳', '🤯', '😴',
  '👍', '👎', '👏', '🙏', '💪', '🤝', '👋', '✌️', '🤞', '👌',
  '❤️', '🧡', '💛', '💚', '💙', '💜', '🔥', '✨', '🎉', '💯',
  '✅', '❌', '⚡', '☕', '🍕', '🚀', '💡', '📌', '🔔', '🎯',
];

Future<String?> showEmojiPicker(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierColor: const Color(0x33000000),
    builder: (_) => const _EmojiPickerDialog(),
  );
}

class _EmojiPickerDialog extends StatelessWidget {
  const _EmojiPickerDialog();

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    return Dialog(
      backgroundColor: p.windowBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 336,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Emoji',
                      style: t.chatTitle.copyWith(color: p.text),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close, size: theme.metrics.iconSize),
                    color: p.icon,
                  ),
                ],
              ),
              SizedBox(
                height: 240,
                child: GridView.count(
                  crossAxisCount: 7,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  children: [
                    for (final emoji in _emojiChoices)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        hoverColor: p.windowBgOver,
                        onTap: () => Navigator.of(context).pop(emoji),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
