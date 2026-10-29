import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../data/clipboard_files.dart';
import '../design/app_metrics.dart';
import '../design/app_theme.dart';
import '../ui/chat/utils/chat_message_parser.dart';
import 'appearance_settings.dart';
import 'media_group_layout.dart';
import 'models.dart';
import 'photo_viewer.dart';
import 'widgets/message_rich_text.dart';
import 'widgets/peer_avatar.dart';

class ConversationPanel extends StatefulWidget {
  const ConversationPanel({
    super.key,
    required this.chat,
    required this.messages,
    this.onBack,
    this.onOpenInfo,
    this.onSend,
    this.onReact,
    this.onAttachPhoto,
    this.onAttachFile,
    this.onSendAttachments,
    this.onDownloadFile,
    this.onOpenFile,
    this.onAcceptRequest,
    this.onDeclineRequest,
    this.onEdit,
    this.onDelete,
    this.onForward,
    this.forwardTargets = const [],
    this.canSend = true,
    this.sending = false,
    this.loading = false,
    this.searchRequest = 0,
  });

  final ChatSummary chat;
  final List<MessageItem> messages;
  final VoidCallback? onBack;

  /// Tapping the avatar/title opens the contact or group info column.
  final VoidCallback? onOpenInfo;
  final void Function(
    String text, {
    int? quotedItemId,
    MessageReply? reply,
  })?
  onSend;
  final void Function(MessageItem message, String emoji)? onReact;
  final VoidCallback? onAttachPhoto;
  final VoidCallback? onAttachFile;

  /// Sends composer attachments (pasted media) with [text] as the caption;
  /// [quotedItemId] carries the reply header when one is open.
  final void Function(
    List<ComposerAttachment> attachments,
    String text, {
    int? quotedItemId,
  })?
  onSendAttachments;

  /// Accepts an incoming document (`/freceive`) and, once it is on disk,
  /// hands it to the OS to open.
  final void Function(MessageItem message)? onDownloadFile;
  final void Function(MessageItem message)? onOpenFile;

  /// Incoming contact request: accept (optionally incognito) or decline.
  final void Function(int requestId, {bool incognito})? onAcceptRequest;
  final VoidCallback? onDeclineRequest;

  /// Saves the edited text of one of my messages (`/_update item`).
  final void Function(MessageItem message, String text)? onEdit;

  /// Removes a message (`/_delete item`); [forEveryone] maps to the core's
  /// `broadcast` mode and is only offered when `CIMeta.deletable` allows it.
  final void Function(MessageItem message, {required bool forEveryone})?
  onDelete;

  /// "Forward" (`/_forward`): the core copies the item into [target] with
  /// `forwardedBy` metadata, the same way the official client does.
  final void Function(MessageItem message, ChatSummary target)? onForward;

  /// Chats the "Forward to" picker lists, newest first.
  final List<ChatSummary> forwardTargets;

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
  final _composeKey = GlobalKey<_ComposeBarState>();
  bool _searching = false;
  MessageItem? _replyTo;
  MessageItem? _editTarget;

  @override
  void didUpdateWidget(covariant ConversationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchRequest != oldWidget.searchRequest) {
      _openSearch();
    }
    if (widget.chat.id != oldWidget.chat.id) {
      _closeSearch();
      _replyTo = null;
      _editTarget = null;
    } else if (_editTarget != null &&
        !widget.messages.any((m) => m.itemId == _editTarget!.itemId)) {
      // The message was deleted (here or by the core) mid-edit.
      _editTarget = null;
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
              (m.displayText.toLowerCase().contains(query) ||
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

  void _startReply(MessageItem message) {
    if (message.itemId == null) return;
    setState(() => _replyTo = message);
  }

  /// Telegram's "Edit": the composer header turns into "Edit message" and the
  /// field holds the original markdown source, so formatting stays editable.
  void _startEdit(MessageItem message) {
    if (message.itemId == null) return;
    setState(() {
      _editTarget = message;
      _replyTo = null;
    });
    _composeKey.currentState?.startEdit(message.text);
  }

  void _cancelEdit() {
    if (_editTarget == null) return;
    setState(() => _editTarget = null);
    _composeKey.currentState?.clearComposer();
  }

  /// Telegram asks before deleting; "Delete for everyone" only appears when
  /// the core would broadcast it (`CIMeta.deletable`).
  Future<void> _confirmDelete(MessageItem message) async {
    final itemId = message.itemId;
    if (itemId == null) return;
    final canDeleteForEveryone = message.deletable;
    final theme = context.appTheme;
    final p = theme.palette;
    final forEveryone = await showDialog<bool>(
      context: context,
      builder: (context) => SimpleDialog(
        key: const ValueKey('delete-dialog'),
        backgroundColor: p.windowBg,
        title: Text(
          'Delete message?',
          style: theme.typography.chatTitle.copyWith(color: p.text),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Text(
              canDeleteForEveryone
                  ? 'This message will be deleted for everyone.'
                  : 'This message will be deleted for you.',
              style: theme.typography.message.copyWith(color: p.textSecondary),
            ),
          ),
          if (canDeleteForEveryone)
            SimpleDialogOption(
              key: const ValueKey('delete-for-everyone'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Delete for everyone',
                style: theme.typography.button.copyWith(color: p.error),
              ),
            ),
          SimpleDialogOption(
            key: const ValueKey('delete-for-me'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Delete for me',
              style: theme.typography.button.copyWith(color: p.error),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: theme.typography.button.copyWith(color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
    if (forEveryone == null || !mounted) return;
    widget.onDelete?.call(message, forEveryone: forEveryone);
    if (_editTarget?.itemId == itemId) {
      setState(() => _editTarget = null);
      _composeKey.currentState?.clearComposer();
    }
  }

  /// Telegram asks for a destination in a "Forward to" panel with a search
  /// field; the message moves as soon as a chat is picked.
  Future<void> _forwardMessage(MessageItem message) async {
    if (message.itemId == null || widget.forwardTargets.isEmpty) return;
    final target = await showDialog<ChatSummary>(
      context: context,
      builder: (context) => _ForwardDialog(chats: widget.forwardTargets),
    );
    if (target == null || !mounted) return;
    widget.onForward?.call(message, target);
  }

  /// Telegram puts a tapped bot command into the composer instead of running
  /// it (`MessageField::insertBotCommand`).
  void _insertCommand(String command) {
    _composeKey.currentState?.insertCommand(command);
  }

  String _replyAuthor(MessageItem message) =>
      message.outgoing ? 'You' : (message.sender ?? widget.chat.name);

  String _replyPreview(MessageItem message) {
    if (message.displayText.isNotEmpty) return message.displayText;
    return message.mediaLabel ?? 'Message';
  }

  /// Opens Telegram's full-screen viewer; an album swipes through its tiles.
  void _openPhoto(MessageItem message, int index) {
    final tiles = message.album.isNotEmpty
        ? message.album
        : [AlbumTile.of(message)];
    showPhotoViewer(context, tiles: tiles, initialIndex: index);
  }

  void _sendFromComposer(String text) {
    final editing = _editTarget;
    if (editing != null) {
      setState(() => _editTarget = null);
      widget.onEdit?.call(editing, text);
      return;
    }
    final reply = _replyTo;
    widget.onSend?.call(
      text,
      quotedItemId: reply?.itemId,
      reply: reply == null
          ? null
          : MessageReply(
              author: _replyAuthor(reply),
              text: _replyPreview(reply),
            ),
    );
    if (reply != null) setState(() => _replyTo = null);
  }

  Future<void> _acceptRequest(int requestId) async {
    final incognito = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = context.appTheme;
        final p = theme.palette;
        return SimpleDialog(
          backgroundColor: p.windowBg,
          title: Text(
            'Accept contact request',
            style: theme.typography.chatTitle.copyWith(color: p.text),
          ),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Accept',
                style: theme.typography.button.copyWith(color: p.accent),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Accept incognito',
                style: theme.typography.button.copyWith(color: p.accent),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: theme.typography.button.copyWith(
                  color: p.textSecondary,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (incognito == null || !mounted) return;
    widget.onAcceptRequest?.call(requestId, incognito: incognito);
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
                    Expanded(
                      child: InkWell(
                        key: const ValueKey('conversation-header'),
                        onTap: widget.onOpenInfo,
                        borderRadius: BorderRadius.circular(6),
                        hoverColor: p.windowBgOver,
                        child: Row(
                          children: [
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
                          ],
                        ),
                      ),
                    ),
                    _IconButton(icon: Icons.search, onTap: _openSearch),
                    PopupMenuButton<_ChatMenuAction>(
                      tooltip: 'More',
                      onSelected: (action) {
                        switch (action) {
                          case _ChatMenuAction.appearance:
                            _openAppearance();
                            break;
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
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
            onReply: _startReply,
            onReact: widget.onReact,
            onEdit: widget.onEdit == null ? null : _startEdit,
            onDelete: widget.onDelete == null ? null : _confirmDelete,
            onForward: widget.onForward == null ? null : _forwardMessage,
            onOpenPhoto: _openPhoto,
            onDownloadFile: widget.onDownloadFile,
            onOpenFile: widget.onOpenFile,
            onCommand: _insertCommand,
          ),
        ),
        if (widget.chat.needsAccept && widget.chat.requestId != null)
          _RequestActionsBar(
            onAccept: () => _acceptRequest(widget.chat.requestId!),
            onDecline: widget.onDeclineRequest,
          )
        else
          _ComposeBar(
            key: _composeKey,
            onSend: _sendFromComposer,
            replyTo: _replyTo,
            replyAuthor: _replyTo == null ? '' : _replyAuthor(_replyTo!),
            replyPreview: _replyTo == null ? '' : _replyPreview(_replyTo!),
            onCancelReply: () => setState(() => _replyTo = null),
            editing: _editTarget != null,
            editPreview: _editTarget?.displayText ?? '',
            onCancelEdit: _cancelEdit,
            onAttachPhoto: widget.onAttachPhoto,
            onAttachFile: widget.onAttachFile,
            onSendAttachments: widget.onSendAttachments == null
                ? null
                : (attachments, text, {int? quotedItemId}) {
                    final reply = _replyTo;
                    widget.onSendAttachments!(
                      attachments,
                      text,
                      quotedItemId: reply?.itemId,
                    );
                    if (reply != null) setState(() => _replyTo = null);
                  },
            canSend: widget.canSend,
            sending: widget.sending,
          ),
      ],
    );
  }
}

enum _ChatMenuAction { appearance }

class _MessageList extends StatefulWidget {
  const _MessageList({
    required this.messages,
    required this.loading,
    required this.emptyLabel,
    this.onReply,
    this.onReact,
    this.onEdit,
    this.onDelete,
    this.onForward,
    this.onOpenPhoto,
    this.onDownloadFile,
    this.onOpenFile,
    this.onCommand,
  });

  final List<MessageItem> messages;
  final bool loading;
  final String emptyLabel;
  final ValueChanged<MessageItem>? onReply;
  final void Function(MessageItem message, String emoji)? onReact;
  final ValueChanged<MessageItem>? onEdit;
  final ValueChanged<MessageItem>? onDelete;
  final ValueChanged<MessageItem>? onForward;
  final void Function(MessageItem message, int index)? onOpenPhoto;
  final void Function(MessageItem message)? onDownloadFile;
  final void Function(MessageItem message)? onOpenFile;
  final void Function(String command)? onCommand;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final _controller = ScrollController();
  final _endKey = GlobalKey();
  int _lastCount = 0;

  /// Telegram counts the mail that arrived below a scrolled-up viewport and
  /// shows it on the corner button (`CornerButtons::updateUnreadCounts`).
  int _unreadBelow = 0;

  /// Telegram keeps the history pinned to the bottom only while the reader is
  /// already there; scrolled up, incoming items leave the viewport alone.
  static const _pinnedSlack = 80.0;
  static const _scrollDuration = Duration(milliseconds: 300);

  /// `historyToDownShownAfter: 480px`, `historyToDownDuration: 150` in
  /// `chat_helpers.style`; the 42px circle comes from `rippleAreaSize`.
  static const _downShownAfter = 480.0;
  static const _downDuration = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _lastCount = widget.messages.length;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  @override
  void didUpdateWidget(covariant _MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length == _lastCount || widget.messages.isEmpty) {
      _lastCount = widget.messages.length;
      return;
    }
    final previousCount = _lastCount;
    _lastCount = widget.messages.length;

    // `AnimatedScroll` in `history_view_list_widget.cpp` slides to the bottom
    // with `easeOutCubic`; incoming mail never yanks the viewport.
    final pinned = _isPinned;
    final sent = widget.messages.lastWhere(
      (message) => !message.isDateSeparator,
      orElse: () => widget.messages.last,
    ).outgoing;
    if (pinned) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
    } else if (sent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _slideToEnd());
    } else {
      final arrived = widget.messages
          .skip(previousCount)
          .where((message) => !message.isDateSeparator && !message.outgoing)
          .length;
      if (arrived > 0) {
        setState(() => _unreadBelow += arrived);
      }
    }
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    if (_unreadBelow == 0) return;
    final position = _controller.position;
    if (!position.hasContentDimensions) return;
    if (position.maxScrollExtent - position.pixels > _pinnedSlack) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _clearUnread());
    } else {
      _clearUnread();
    }
  }

  void _clearUnread() {
    if (!mounted || _unreadBelow == 0) return;
    setState(() => _unreadBelow = 0);
  }

  bool get _isPinned {
    if (!_controller.hasClients) return true;
    final position = _controller.position;
    if (!position.hasContentDimensions) return true;
    return position.maxScrollExtent - position.pixels <= _pinnedSlack;
  }

  /// The list is lazy, so `maxScrollExtent` is an estimate until the tail is
  /// built; reveal the keyed last row instead, then settle on the real end.
  void _jumpToEnd({int attempt = 0}) {
    if (!mounted || !_controller.hasClients) return;
    final end = _endKey.currentContext;
    if (end != null) {
      Scrollable.ensureVisible(end, alignment: 1);
      final max = _controller.position.maxScrollExtent;
      if (max > _controller.offset) _controller.jumpTo(max);
      return;
    }
    _controller.jumpTo(_controller.position.maxScrollExtent);
    if (attempt < 3) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpToEnd(attempt: attempt + 1),
      );
    }
  }

  Future<void> _slideToEnd() async {
    for (var pass = 0; pass < 3; pass++) {
      if (!mounted || !_controller.hasClients) return;
      final duration = pass == 0
          ? _scrollDuration
          : const Duration(milliseconds: 120);
      final end = _endKey.currentContext;
      if (end != null) {
        await Scrollable.ensureVisible(
          end,
          alignment: 1,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      } else {
        await _controller.animateTo(
          _controller.position.maxScrollExtent,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
      if (!mounted || !_controller.hasClients) return;
      if (_controller.position.maxScrollExtent - _controller.offset <= 0.5) {
        return;
      }
    }
    _jumpToEnd();
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
      child: Stack(
        children: [
          ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            itemCount: widget.messages.length,
            itemBuilder: (context, index) {
              final message = widget.messages[index];
              final Widget row;
              if (message.isDateSeparator) {
                row = Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
                  child: Center(child: _Pill(label: message.text)),
                );
              } else if (message.isSystem) {
                row = _ServiceMessage(text: message.text);
              } else {
                row = _MessageRow(
                  message: message,
                  bubbleMargin: m.bubbleMargin,
                  onReply: widget.onReply,
                  onReact: widget.onReact,
                  onEdit: widget.onEdit,
                  onDelete: widget.onDelete,
                  onForward: widget.onForward,
                  onOpenPhoto: widget.onOpenPhoto,
                  onDownloadFile: widget.onDownloadFile,
                  onOpenFile: widget.onOpenFile,
                  onCommand: widget.onCommand,
                );
              }
              return index == widget.messages.length - 1
                  ? KeyedSubtree(key: _endKey, child: row)
                  : row;
            },
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final position = _controller.hasClients
                    ? _controller.position
                    : null;
                final shown =
                    position == null ||
                    !position.hasContentDimensions ||
                    position.maxScrollExtent - position.pixels >
                        _downShownAfter;
                return IgnorePointer(
                  ignoring: !shown,
                  child: AnimatedOpacity(
                    key: const ValueKey('jumpDown'),
                    duration: _downDuration,
                    curve: Curves.easeOutCubic,
                    opacity: shown ? 1 : 0,
                    child: AnimatedScale(
                      duration: _downDuration,
                      curve: Curves.easeOutCubic,
                      scale: shown ? 1 : 0.78,
                      child: _JumpDownButton(
                        unread: _unreadBelow,
                        onTap: _slideToEnd,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// `Ui::JumpDownButton` from `ui/controls/jump_down_button.cpp`: a 42px
/// accent circle with a down arrow and an unread badge on its top-right.
class _JumpDownButton extends StatelessWidget {
  const _JumpDownButton({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final label = unread > 99 ? '99+' : '$unread';
    return Semantics(
      button: true,
      label: 'Jump to bottom',
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: p.accent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      size: 22,
                      color: p.onAccent,
                    ),
                  ),
                  if (unread > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        key: const ValueKey('jumpDownBadge'),
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: p.badge,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: p.chatWallpaper, width: 2),
                        ),
                        child: Text(
                          label,
                          style: theme.typography.badge.copyWith(
                            color: p.badgeText,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
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

/// Telegram keeps service lines narrow and centered instead of stretching
/// them across the whole conversation.
class _ServiceMessage extends StatelessWidget {
  const _ServiceMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final screen = MediaQuery.sizeOf(context).width;
    // `history_view_service_message.cpp`: up to 542px wide with 12px inner
    // padding, i.e. 498px of text (`msgServiceMargin`/`msgServicePadding`).
    final maxWidth = math.min(
      theme.metrics.compact ? screen * 0.82 : 498.0,
      screen - 32,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 3, 12, 4),
            decoration: BoxDecoration(
              color: p.serviceBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.typography.service.copyWith(color: p.serviceText),
            ),
          ),
        ),
      ),
    );
  }
}

/// Exactly the reactions the SimpleX core accepts. `mrEmojiChar` in
/// `src/Simplex/Chat/Protocol.hs` validates a single char, and the heart is
/// stored as plain U+2764 — the emoji presentation selector (U+FE0F) would
/// make the reaction JSON invalid and the core would reject it.
const _reactionValues = <String>['👍', '👎', '😀', '😂', '😢', '❤', '🚀', '✅'];

/// The official clients render the heart with its presentation selector.
String reactionLabel(String emoji) => emoji == '❤' ? '❤️' : emoji;

class _MessageRow extends StatefulWidget {
  const _MessageRow({
    required this.message,
    required this.bubbleMargin,
    this.onReply,
    this.onReact,
    this.onEdit,
    this.onDelete,
    this.onForward,
    this.onOpenPhoto,
    this.onDownloadFile,
    this.onOpenFile,
    this.onCommand,
  });

  final MessageItem message;
  final EdgeInsets bubbleMargin;
  final ValueChanged<MessageItem>? onReply;
  final void Function(MessageItem message, String emoji)? onReact;
  final ValueChanged<MessageItem>? onEdit;
  final ValueChanged<MessageItem>? onDelete;
  final ValueChanged<MessageItem>? onForward;
  final void Function(MessageItem message, int index)? onOpenPhoto;
  final void Function(MessageItem message)? onDownloadFile;
  final void Function(MessageItem message)? onOpenFile;
  final void Function(String command)? onCommand;

  @override
  State<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<_MessageRow> {
  bool get _hasActions =>
      widget.message.displayText.isNotEmpty ||
      (widget.message.itemId != null &&
          (widget.onReply != null ||
              widget.onReact != null ||
              widget.onEdit != null ||
              widget.onDelete != null ||
              widget.onForward != null));

  /// Mirrors Telegram desktop: right click (or long press) opens a floating
  /// emoji pill above a rounded card with the available item actions.
  Future<void> _openActions(BuildContext context, Offset position) async {
    if (!_hasActions) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final screen = overlay.size;
    final hasItem = widget.message.itemId != null;
    final canReact = hasItem && widget.onReact != null;
    final canReply = hasItem && widget.onReply != null;
    final canCopy = widget.message.displayText.isNotEmpty;
    // Telegram hides "Edit" for media without an editable caption, for
    // timers and for other people's messages; the core's `editable` flag
    // already covers the last two (sent, under 24h, not forwarded).
    final isMedia =
        widget.message.album.isNotEmpty ||
        widget.message.imageBytes != null ||
        widget.message.imagePath != null ||
        widget.message.fileName != null;
    final canEdit = hasItem &&
        widget.onEdit != null &&
        widget.message.editable &&
        widget.message.text.isNotEmpty &&
        !isMedia;
    final canDelete = hasItem && widget.onDelete != null;
    // Telegram forwards any message, including media and other people's.
    final canForward = hasItem && widget.onForward != null;
    final cardItems = (canReply ? 1 : 0) +
        (canCopy ? 1 : 0) +
        (canForward ? 1 : 0) +
        (canEdit ? 1 : 0) +
        (canDelete ? 1 : 0);

    const cardWidth = _MessageActionsMenu.width;
    final menuWidth = canReact
        ? _MessageActionsMenu.stripWidth
        : cardWidth;
    const pillHeight = 40.0;
    const gap = 8.0;
    final cardHeight = cardItems * 44.0 + 8;
    final total = (canReact ? pillHeight + gap : 0) + cardHeight;
    final left = (position.dx - menuWidth / 2)
        .clamp(8.0, math.max(8.0, screen.width - menuWidth - 8))
        .toDouble();
    var top = position.dy - total - 12;
    if (top < 8) top = position.dy + 12;
    // `Ui::PopupMenu` grows out of the corner closest to the anchor.
    final origin = Alignment(
      position.dx < left + menuWidth / 2 ? -1 : 1,
      top < position.dy ? 1 : -1,
    );

    final picked = await showGeneralDialog<Object>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss message actions',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, _, _) => Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: _MessageActionsMenu(
              message: widget.message,
              canReply: canReply,
              canReact: canReact,
              canForward: canForward,
              canEdit: canEdit,
              canDelete: canDelete,
            ),
          ),
        ],
      ),
      transitionBuilder: (_, animation, _, child) => _ActionsMenuAppear(
        animation: animation,
        origin: origin,
        child: child,
      ),
    );
    if (!mounted || picked == null) return;
    if (picked is String) {
      widget.onReact?.call(widget.message, picked);
    } else if (picked == _MessageAction.reply) {
      widget.onReply?.call(widget.message);
    } else if (picked == _MessageAction.copy) {
      await Clipboard.setData(
        ClipboardData(text: widget.message.displayText),
      );
    } else if (picked == _MessageAction.forward) {
      widget.onForward?.call(widget.message);
    } else if (picked == _MessageAction.edit) {
      widget.onEdit?.call(widget.message);
    } else if (picked == _MessageAction.delete) {
      widget.onDelete?.call(widget.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final m = theme.metrics;
    final message = widget.message;

    final bottomGap = message.lastInGroup ? m.messageGroupGap : m.attachedGap;
    final out = message.outgoing;

    final bubble = ConstrainedBox(
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
        onReact: widget.onReact,
        onOpenPhoto: widget.onOpenPhoto,
        onDownloadFile: widget.onDownloadFile,
        onOpenFile: widget.onOpenFile,
        onCommand: widget.onCommand,
      ),
    );

    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _openActions(context, details.globalPosition),
      onLongPressStart: (details) =>
          _openActions(context, details.globalPosition),
      child: Padding(
        padding: EdgeInsets.only(
          left: widget.bubbleMargin.left,
          right: widget.bubbleMargin.right,
          bottom: bottomGap,
        ),
        child: Align(
          alignment: out ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: out
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [bubble],
          ),
        ),
      ),
    );
  }
}

enum _MessageAction { reply, copy, forward, edit, delete }

/// `Ui::PanelAnimation` for `Ui::PopupMenu`: the panel expands from 50% width
/// and 30% height with 20% opacity, then fades up. Width runs for 60% of the
/// 200ms show duration, height for 90%, opacity for 30%, all `easeOutCirc`
/// (`defaultPanelAnimation` in `widgets.style`, `panel_animation.cpp`).
/// Hiding is opacity-only over 150ms.
class _ActionsMenuAppear extends StatelessWidget {
  const _ActionsMenuAppear({
    required this.animation,
    required this.origin,
    required this.child,
  });

  final Animation<double> animation;
  final Alignment origin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        if (animation.status == AnimationStatus.reverse) {
          return Opacity(opacity: t, child: child);
        }
        double part(double end) =>
            Curves.easeOutCirc.transform((t / end).clamp(0.0, 1.0));
        return Opacity(
          opacity: 0.2 + 0.8 * part(0.3),
          child: Transform(
            key: const ValueKey('message-actions-pop'),
            alignment: origin,
            transform: Matrix4.diagonal3Values(
              0.5 + 0.5 * part(0.6),
              0.3 + 0.7 * part(0.9),
              1,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _MessageActionsMenu extends StatelessWidget {
  const _MessageActionsMenu({
    required this.message,
    required this.canReply,
    required this.canReact,
    required this.canForward,
    required this.canEdit,
    required this.canDelete,
  });

  static const width = 244.0;
  // `history_view_reactions_selector.cpp`: strip height 40, 32px cells with a
  // 7px skip between them, 26px emoji.
  static const stripWidth = 312.0;

  final MessageItem message;
  final bool canReply;
  final bool canReact;
  final bool canForward;
  final bool canEdit;
  final bool canDelete;

  static const _shadow = [
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 18,
      offset: Offset(0, 4),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;

    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (canReact) ...[
            Container(
              key: const ValueKey('reaction-strip'),
              width: stripWidth,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: p.windowBg,
                borderRadius: BorderRadius.circular(20),
                boxShadow: _shadow,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in _reactionValues)
                    _StripEmoji(
                      emoji: emoji,
                      onTap: () => Navigator.of(context).pop(emoji),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Container(
            key: const ValueKey('actions-card'),
            width: width,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: p.windowBg,
              borderRadius: BorderRadius.circular(10),
              boxShadow: _shadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canReply)
                  _MenuRow(
                    icon: Icons.reply,
                    label: 'Reply',
                    style: t.message.copyWith(color: p.text),
                    iconColor: p.icon,
                    onTap: () =>
                        Navigator.of(context).pop(_MessageAction.reply),
                  ),
                if (message.text.isNotEmpty)
                  _MenuRow(
                    icon: Icons.content_copy,
                    label: 'Copy text',
                    style: t.message.copyWith(color: p.text),
                    iconColor: p.icon,
                    onTap: () => Navigator.of(context).pop(_MessageAction.copy),
                  ),
                if (canForward)
                  _MenuRow(
                    icon: Icons.forward,
                    label: 'Forward',
                    style: t.message.copyWith(color: p.text),
                    iconColor: p.icon,
                    onTap: () =>
                        Navigator.of(context).pop(_MessageAction.forward),
                  ),
                if (canEdit)
                  _MenuRow(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    style: t.message.copyWith(color: p.text),
                    iconColor: p.icon,
                    onTap: () => Navigator.of(context).pop(_MessageAction.edit),
                  ),
                if (canDelete)
                  _MenuRow(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    style: t.message.copyWith(color: p.error),
                    iconColor: p.error,
                    onTap: () =>
                        Navigator.of(context).pop(_MessageAction.delete),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.style,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final TextStyle style;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return InkWell(
      onTap: onTap,
      hoverColor: theme.palette.windowBgOver,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Telegram's "Forward to" panel: a searchable chat list where picking a row
/// forwards right away (`history_view_forward_panel.cpp`).
class _ForwardDialog extends StatefulWidget {
  const _ForwardDialog({required this.chats});

  final List<ChatSummary> chats;

  @override
  State<_ForwardDialog> createState() => _ForwardDialogState();
}

class _ForwardDialogState extends State<_ForwardDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ChatSummary> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return widget.chats;
    return widget.chats
        .where((chat) => chat.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    final chats = _visible;
    return Dialog(
      key: const ValueKey('forward-dialog'),
      backgroundColor: p.windowBg,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Forward to',
                      style: t.chatTitle.copyWith(color: p.text),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: Icon(Icons.close, size: 20, color: p.icon),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const ValueKey('forward-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: t.message.copyWith(color: p.text),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search',
                  hintStyle: t.message.copyWith(color: p.textSecondary),
                  prefixIcon: Icon(Icons.search, size: 20, color: p.icon),
                  filled: true,
                  fillColor: p.searchBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Flexible(
              child: chats.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No chats found',
                        style: t.message.copyWith(color: p.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        return InkWell(
                          key: ValueKey('forward-target-${chat.id}'),
                          onTap: () => Navigator.of(context).pop(chat),
                          child: SizedBox(
                            height: 56,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  PeerAvatar(
                                    seed: chat.id,
                                    title: chat.name,
                                    size: 36,
                                    imageBytes: chat.avatarBytes,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          chat.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: t.chatTitle.copyWith(
                                            color: p.text,
                                            fontSize: 14,
                                          ),
                                        ),
                                        if (chat.preview.isNotEmpty)
                                          Text(
                                            chat.preview,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: t.messageMeta.copyWith(
                                              color: p.textSecondary,
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
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StripEmoji extends StatefulWidget {
  const _StripEmoji({required this.emoji, required this.onTap});
  final String emoji;
  final VoidCallback onTap;

  @override
  State<_StripEmoji> createState() => _StripEmojiState();
}

class _StripEmojiState extends State<_StripEmoji> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            // Telegram's strip lifts the hovered emoji to 1.24x over 200ms
            // (kHoverScale / kHoverScaleDuration in history_view_reactions_strip).
            child: AnimatedScale(
              key: ValueKey('strip-emoji-${widget.emoji}'),
              scale: _hovered ? 1.24 : 1,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Text(
                reactionLabel(widget.emoji),
                style: const TextStyle(fontSize: 26),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionChips extends StatelessWidget {
  const _ReactionChips({required this.message, this.onReact});

  final MessageItem message;
  final void Function(MessageItem message, String emoji)? onReact;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    final out = message.outgoing;
    final bubbleBg = out ? p.bubbleOut : p.bubbleIn;
    return Wrap(
      alignment: out ? WrapAlignment.end : WrapAlignment.start,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final reaction in message.reactions)
          _ReactionChip(
            key: ValueKey('reaction-chip-${reaction.emoji}'),
            reaction: reaction,
            countStyle: t.messageMeta.copyWith(
              fontSize: 12,
              color: reaction.mine ? p.onAccent : p.link,
            ),
            background: reaction.mine
                ? p.accent
                : Color.alphaBlend(
                    Colors.white.withValues(alpha: out ? 0.18 : 0.12),
                    bubbleBg,
                  ),
            onTap: onReact == null || !_reactionValues.contains(reaction.emoji)
                ? null
                : () => onReact!(message, reaction.emoji),
          ),
      ],
    );
  }
}

class _ReactionChip extends StatefulWidget {
  const _ReactionChip({
    super.key,
    required this.reaction,
    required this.countStyle,
    required this.background,
    this.onTap,
  });

  final MessageReaction reaction;
  final TextStyle countStyle;
  final Color background;
  final VoidCallback? onTap;

  @override
  State<_ReactionChip> createState() => _ReactionChipState();
}

class _ReactionChipState extends State<_ReactionChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  )..forward();

  late final Animation<double> _scale = Tween<double>(
    begin: 0.7,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reaction = widget.reaction;
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: widget.onTap,
          child: Container(
            height: 22,
            padding: const EdgeInsets.fromLTRB(5, 0, 6, 0),
            decoration: BoxDecoration(
              // Telegram desktop reaction tag: the chosen reaction uses the
              // file-info blue, the rest tint the bubble by 12% (in) or
              // 18% (out) white (`history_view_reactions.cpp`).
              color: widget.background,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reactionLabel(reaction.emoji),
                  style: const TextStyle(fontSize: 14, height: 1.1),
                ),
                if (reaction.count > 1) ...[
                  const SizedBox(width: 3),
                  Text('${reaction.count}', style: widget.countStyle),
                ],
              ],
            ),
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
    this.onReact,
    this.onOpenPhoto,
    this.onDownloadFile,
    this.onOpenFile,
    this.onCommand,
  });

  final MessageItem message;
  final bool firstInGroup;
  final bool lastInGroup;
  final void Function(MessageItem message, String emoji)? onReact;

  /// Opens the photo viewer on the tapped tile of a photo/album bubble.
  final void Function(MessageItem message, int index)? onOpenPhoto;

  /// Document bubble actions: accept a pending download, or open a file that
  /// already sits on disk.
  final void Function(MessageItem message)? onDownloadFile;
  final void Function(MessageItem message)? onOpenFile;

  /// Tapped bot command from the bubble text.
  final void Function(String command)? onCommand;

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

    final mediaLabel = message.mediaLabel;
    final hasMedia = mediaLabel != null &&
        (message.imageBytes != null ||
            (message.imagePath != null &&
                File(message.imagePath!).existsSync()));
    final isDocument = message.isDocument;

    Widget timeRow({Color? color, Color? tickColor}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // `BottomInfo::layoutDateText` prefixes the date with "edited ".
          if (message.edited)
            Text(
              'edited ',
              key: const ValueKey('edited-label'),
              style: t.messageMeta.copyWith(color: color ?? metaColor),
            ),
          Text(
            message.time,
            style: t.messageMeta.copyWith(color: color ?? metaColor),
          ),
          if (out) ...[
            const SizedBox(width: 3),
            _StatusIcon(
              status: message.status,
              color: color == null ? null : tickColor ?? color,
            ),
          ],
        ],
      );
    }

    final reactionsBlock = message.reactions.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 5),
            child: _ReactionChips(message: message, onReact: onReact),
          );

    Widget bodyText(
      TextStyle style, {
      int? maxLines,
      TextOverflow overflow = TextOverflow.clip,
    }) => MessageRichText(
      spans: message.spans,
      text: message.displayText,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      onCommand: onCommand,
    );

    // Photos and videos fill the bubble edge to edge like Telegram: the
    // caption, time and reactions keep the bubble padding underneath, and a
    // photo without a caption carries the time over a scrim in the corner.
    final overlayTime = hasMedia && message.text.isEmpty &&
        message.reactions.isEmpty;

    final Widget body;
    if (hasMedia) {
      final timePill = overlayTime
          ? _MediaTimePill(
              child: timeRow(color: p.onAccent, tickColor: p.onAccent),
            )
          : null;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.album.isNotEmpty)
            _AlbumPreview(
              message: message,
              overlay: timePill,
              onOpen: onOpenPhoto == null
                  ? null
                  : (index) => onOpenPhoto!(message, index),
            )
          else
            _MediaPreview(
              message: message,
              overlay: timePill,
              onTap: onOpenPhoto == null
                  ? null
                  : () => onOpenPhoto!(message, 0),
            ),
          if (!overlayTime)
            Padding(
              padding: m.bubblePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.text.isNotEmpty) ...[
                    bodyText(t.message.copyWith(color: textColor)),
                    const SizedBox(height: 2),
                  ],
                  timeRow(),
                  ?reactionsBlock,
                ],
              ),
            ),
        ],
      );
    } else if (isDocument) {
      // Telegram's file bubble: the 44 px icon and the two text lines use
      // `msgFileLayout.padding` (12,8,10,8) while a caption and the meta row
      // fall back to the normal message padding below
      // (`history_view_document.cpp`, `chat.style`).
      // Telegram keeps the time on the status line unless a caption needs its
      // own row (`Document::countCurrentSize`); reactions are attached under
      // the file rather than replacing that line.
      final inlineMeta = message.text.isEmpty;
      final Widget? captionBlock;
      if (message.text.isNotEmpty) {
        captionBlock = Padding(
          padding: m.bubblePadding.copyWith(top: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 2),
              bodyText(t.message.copyWith(color: textColor)),
              const SizedBox(height: 2),
              timeRow(),
              ?reactionsBlock,
            ],
          ),
        );
      } else if (message.reactions.isNotEmpty) {
        captionBlock = Padding(
          padding: m.bubblePadding.copyWith(top: 0, bottom: 6),
          child: _ReactionChips(message: message, onReact: onReact),
        );
      } else {
        captionBlock = null;
      }
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _DocumentCard(
            message: message,
            showDownload: !message.outgoing && message.filePath == null,
            statusStyle: t.messageMeta.copyWith(color: metaColor),
            nameStyle: t.sender.copyWith(color: textColor),
            inlineMeta: inlineMeta
                ? timeRow(color: metaColor)
                : null,
            onTap: () {
              if (message.filePath == null) {
                if (!message.outgoing) onDownloadFile?.call(message);
              } else {
                onOpenFile?.call(message);
              }
            },
          ),
          ?captionBlock,
        ],
      );
    } else {
      body = Padding(
        padding: m.bubblePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mediaLabel != null) ...[
              Text(
                mediaLabel,
                style: t.messageMeta.copyWith(color: textColor),
              ),
              const SizedBox(height: 2),
            ],
            if (message.text.isNotEmpty)
              bodyText(t.message.copyWith(color: textColor)),
            const SizedBox(height: 2),
            timeRow(),
            ?reactionsBlock,
          ],
        ),
      );
    }

    return Container(
      key: ValueKey('message-bubble-${message.itemId ?? message.hashCode}'),
      clipBehavior: Clip.antiAlias,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Telegram paints the forwarded header in the accent colour above
          // the quote and the text (`ForwardedMessage` in `history_item`).
          if (message.forwarded)
            Padding(
              padding: m.bubblePadding.copyWith(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forward, size: 14, color: p.link),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      message.forwardedFrom == null
                          ? 'Forwarded'
                          : 'Forwarded from ${message.forwardedFrom}',
                      key: const ValueKey('forwarded-label'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.sender.copyWith(
                        color: p.link,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (message.reply != null) ...[
            Padding(
              padding: m.bubblePadding.copyWith(bottom: 4),
              child: Container(
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
                    MessageRichText(
                      spans: message.reply!.spans,
                      text: message.reply!.displayText,
                      style: t.messageMeta.copyWith(color: textColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      interactive: false,
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (message.sender != null && firstInGroup && !out) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                m.bubblePadding.left,
                0,
                m.bubblePadding.right,
                2,
              ),
              child: Text(
                message.sender!,
                style: t.sender.copyWith(color: p.link),
              ),
            ),
          ],
          body,
        ],
      ),
    );
  }
}

class _MediaTimePill extends StatelessWidget {
  const _MediaTimePill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 1, 5, 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(11),
      ),
      child: child,
    );
  }
}

class _MediaPreview extends StatefulWidget {
  const _MediaPreview({required this.message, this.overlay, this.onTap});

  final MessageItem message;
  final Widget? overlay;
  final VoidCallback? onTap;

  @override
  State<_MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<_MediaPreview> {
  double? _aspect;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void didUpdateWidget(covariant _MediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.imageBytes != widget.message.imageBytes) {
      _aspect = null;
      _measure();
    }
  }

  /// Telegram sizes photo bubbles from the file's aspect ratio, capped by the
  /// bubble width (`history_view_photo.cpp`).
  void _measure() {
    final bytes = widget.message.imageBytes;
    if (bytes == null) return;
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width <= 0 || decoded.height <= 0) return;
      final aspect = decoded.width / decoded.height;
      if (mounted) {
        setState(() => _aspect = aspect);
      } else {
        _aspect = aspect;
      }
    } catch (_) {
      // Undecodable previews keep the 4:3 placeholder box.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final m = theme.metrics;
    final bytes = widget.message.imageBytes;
    final path = widget.message.imagePath;

    // Telegram paints the downloaded file once it is on disk and only falls
    // back to the inline thumbnail while the transfer runs
    // (`history_view_photo.cpp` loads `_dataMedia`). Videos need a player, so
    // they keep the preview bytes.
    final file = path != null &&
            !widget.message.isVideo &&
            File(path).existsSync()
        ? File(path)
        : null;

    Widget previewFallback() {
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _MediaPlaceholder(
            isVideo: widget.message.isVideo,
          ),
        );
      }
      return _MediaPlaceholder(isVideo: widget.message.isVideo);
    }

    Widget? image;
    if (file != null) {
      image = Image.file(
        file,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => previewFallback(),
      );
    } else if (bytes != null) {
      image = previewFallback();
    }

    final aspect = _aspect ?? 4 / 3;
    final transferring = widget.message.isTransferring;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math.min(m.bubbleMaxWidth, constraints.maxWidth);
        var width = maxWidth;
        var height = width / aspect;
        if (height > maxWidth) {
          height = maxWidth;
          width = height * aspect;
        }
        final content = Stack(
          fit: StackFit.expand,
          children: [
            image ??
                _MediaPlaceholder(isVideo: widget.message.isVideo),
            if (transferring)
              Center(
                child: _TransferRing(
                  progress: widget.message.transferFraction,
                ),
              ),
            if (widget.overlay != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: widget.overlay!,
              ),
          ],
        );
        return SizedBox(
          width: width,
          height: height,
          child: widget.onTap == null
              ? content
              : MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    key: const ValueKey('media-preview'),
                    onTap: widget.onTap,
                    child: content,
                  ),
                ),
        );
      },
    );
  }
}

/// Telegram's grouped-media mosaic (`GroupedMedia`,
/// `history_view_media_grouped.cpp:143`): the tiles are laid out at the
/// maximal 430 px width and scaled down together with the 4 px skip, and the
/// bubble's own rounding clips the outer corners.
class _AlbumPreview extends StatefulWidget {
  const _AlbumPreview({required this.message, this.overlay, this.onOpen});

  final MessageItem message;
  final Widget? overlay;
  final void Function(int index)? onOpen;

  @override
  State<_AlbumPreview> createState() => _AlbumPreviewState();
}

class _AlbumPreviewState extends State<_AlbumPreview> {
  List<double?> _aspects = const [];

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void didUpdateWidget(covariant _AlbumPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _measure();
  }

  /// Precise geometry needs the natural ratio of every tile, the same input
  /// `Photo::sizeForGroupingOptimal` gives the layouter. Each preview is
  /// decoded once; later timeline refetches reuse the measured value.
  void _measure() {
    final tiles = widget.message.album;
    if (_aspects.length != tiles.length) {
      _aspects = List<double?>.filled(tiles.length, null);
    }
    var updated = false;
    for (var i = 0; i < tiles.length; i++) {
      if (_aspects[i] != null) continue;
      final bytes = tiles[i].bytes;
      if (bytes == null) continue;
      try {
        final decoded = img.decodeImage(bytes);
        if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
          continue;
        }
        _aspects[i] = decoded.width / decoded.height;
        updated = true;
      } catch (_) {
        // Undecodable previews keep the 4:3 box.
      }
    }
    if (!updated) return;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.appTheme.metrics;
    final tiles = widget.message.album;
    final ratios = [
      for (var i = 0; i < tiles.length; i++)
        i < _aspects.length ? (_aspects[i] ?? 4 / 3) : 4 / 3,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math
            .min(m.bubbleMaxWidth, constraints.maxWidth)
            .round();
        final layout = scaleGroupLayout(layoutMediaGroup(ratios), width);
        final height = layout.fold<int>(
          0,
          (value, tile) => math.max(value, tile.bottom),
        );
        return SizedBox(
          width: width.toDouble(),
          height: height.toDouble(),
          child: Stack(
            children: [
              for (var i = 0; i < layout.length; i++)
                Positioned(
                  left: layout[i].left.toDouble(),
                  top: layout[i].top.toDouble(),
                  width: layout[i].width.toDouble(),
                  height: layout[i].height.toDouble(),
                  child: MouseRegion(
                    cursor: widget.onOpen == null
                        ? MouseCursor.defer
                        : SystemMouseCursors.click,
                    child: GestureDetector(
                      key: ValueKey('album-tile-$i'),
                      onTap: widget.onOpen == null
                          ? null
                          : () => widget.onOpen!(i),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _AlbumTileImage(tile: tiles[i]),
                          if (tiles[i].isTransferring)
                            Center(
                              child: _TransferRing(
                                progress: tiles[i].transferFraction,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (widget.overlay != null)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: widget.overlay!,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AlbumTileImage extends StatelessWidget {
  const _AlbumTileImage({required this.tile});

  final AlbumTile tile;

  @override
  Widget build(BuildContext context) {
    final path = tile.path;
    final file =
        path != null && !tile.isVideo && File(path).existsSync()
        ? File(path)
        : null;
    Widget previewFallback() {
      final bytes = tile.bytes;
      if (bytes == null) return _MediaPlaceholder(isVideo: tile.isVideo);
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _MediaPlaceholder(isVideo: tile.isVideo),
      );
    }

    if (file != null) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => previewFallback(),
      );
    }
    return previewFallback();
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({this.isVideo = false});

  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    final p = context.appTheme.palette;
    return ColoredBox(
      color: p.windowBgOver,
      child: Center(
        child: Icon(
          isVideo ? Icons.videocam_outlined : Icons.image_outlined,
          size: 32,
          color: p.icon,
        ),
      ),
    );
  }
}

/// Telegram Desktop's document bubble (`history_view_document.cpp`): a 44 px
/// accent disc with the file glyph, the name in semibold, and the size or
/// transfer bytes underneath. A pending download gets the corner disc from
/// `Document::drawCornerDownload`; a running transfer turns the disc into a
/// radial. The width floor is `msgFileMinWidth` (268 px) and grows with the
/// name up to the bubble limit.
class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.message,
    required this.showDownload,
    required this.nameStyle,
    required this.statusStyle,
    required this.onTap,
    this.inlineMeta,
  });

  final MessageItem message;
  final bool showDownload;
  final TextStyle nameStyle;
  final TextStyle statusStyle;

  /// Time and ticks on the status line when the file has no caption/reactions.
  final Widget? inlineMeta;
  final VoidCallback onTap;

  static const double _iconSize = 44;
  static const double _overhead = 12 + _iconSize + 11 + 10;
  static const double _minWidth = 268;

  String get _status {
    if (message.transferStatus == 'rcvError' ||
        message.transferStatus == 'sndError') {
      return 'Failed';
    }
    final total = message.transferTotal ?? message.fileSize;
    if (message.isTransferring) {
      final done = message.transferProgress;
      if (done != null && total != null) {
        return '${_formatFileSize(done)} / ${_formatFileSize(total)}';
      }
    }
    return total == null ? '' : _formatFileSize(total);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final failed = message.transferStatus == 'rcvError' ||
        message.transferStatus == 'sndError';
    final statusStyle = failed
        ? this.statusStyle.copyWith(color: theme.palette.error)
        : this.statusStyle;
    final enabled =
        !message.isTransferring &&
        (message.filePath != null || !message.outgoing);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : theme.metrics.bubbleMaxWidth;
        final nameWidth = _textWidth(context, message.fileName ?? '', nameStyle);
        final statusWidth = _textWidth(context, _status, statusStyle);
        final width = math.min(
          maxWidth,
          math.max(
            _minWidth,
            _overhead +
                math.max(
                  nameWidth,
                  statusWidth + (inlineMeta == null ? 0 : 56),
                ),
          ),
        );
        final card = SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Row(
              children: [
                _fileIcon(context),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.fileName ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle,
                      ),
                      const SizedBox(height: 2),
                      if (inlineMeta == null)
                        Text(
                          _status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: statusStyle,
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: statusStyle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            inlineMeta!,
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        if (!enabled) return card;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: const ValueKey('document-card'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: card,
          ),
        );
      },
    );
  }

  Widget _fileIcon(BuildContext context) {
    final p = context.appTheme.palette;
    return SizedBox(
      width: _iconSize,
      height: _iconSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
              child: Center(
                child: Icon(
                  Icons.insert_drive_file_outlined,
                  size: 23,
                  color: p.onAccent,
                ),
              ),
            ),
          ),
          if (message.isTransferring)
            Positioned.fill(
              // Telegram insets the radial by `msgFileRadialLine` (3px) so it
              // rings the glyph inside the disc instead of outlining it.
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: CircularProgressIndicator(
                  value: message.transferFraction,
                  strokeWidth: 3,
                  color: p.onAccent,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
          if (showDownload && !message.isTransferring)
            Positioned(
              right: -4,
              bottom: -4,
              child: Tooltip(
                message: 'Download',
                child: Container(
                  key: const ValueKey('document-download'),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: p.accent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: message.outgoing ? p.bubbleOut : p.bubbleIn,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_downward,
                    size: 12,
                    color: p.onAccent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

double _textWidth(BuildContext context, String text, TextStyle style) {
  if (text.isEmpty) return 0;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
  )..layout();
  return painter.width;
}

String _formatFileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

/// Telegram Desktop's upload/download indicator over a media thumbnail: a
/// translucent 44 px disc with a 3 px radial arc
/// (`history_view_photo.cpp`, `msgFileLayout.thumbSize`). The core has no
/// cancel command wired yet, so only the arc is drawn.
class _TransferRing extends StatelessWidget {
  const _TransferRing({this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 44,
        height: 44,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0x73000000),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: CircularProgressIndicator(
              value: progress ?? 0,
              strokeWidth: 3,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status, this.color});

  final MessageStatus status;

  /// Overrides the palette colours, e.g. white ticks on a media scrim.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final metaColor = color ?? p.timeOut;

    final (IconData icon, Color iconColor) = switch (status) {
      MessageStatus.none => (Icons.done, metaColor),
      MessageStatus.sending => (Icons.schedule, metaColor),
      MessageStatus.failed => (Icons.error_outline, const Color(0xFFFF3B30)),
      MessageStatus.sent => (Icons.done, metaColor),
      MessageStatus.delivered => (Icons.done_all, metaColor),
      MessageStatus.read => (Icons.done_all, color ?? p.ticksOut),
    };

    return Icon(icon, size: 14, color: iconColor);
  }
}

class _RequestActionsBar extends StatelessWidget {
  const _RequestActionsBar({required this.onAccept, this.onDecline});

  final VoidCallback onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: p.composeBg,
        border: Border(top: BorderSide(color: p.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onDecline,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.close, size: 20, color: p.error),
                  const SizedBox(height: 2),
                  Text('Decline', style: t.button.copyWith(color: p.error)),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 36, color: p.divider),
          Expanded(
            child: InkWell(
              onTap: onAccept,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check, size: 20, color: p.accent),
                  const SizedBox(height: 2),
                  Text('Accept', style: t.button.copyWith(color: p.accent)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposeBar extends StatefulWidget {
  const _ComposeBar({
    super.key,
    required this.onSend,
    required this.replyTo,
    required this.replyAuthor,
    required this.replyPreview,
    required this.onCancelReply,
    required this.canSend,
    required this.sending,
    this.editing = false,
    this.editPreview = '',
    this.onCancelEdit,
    this.onAttachPhoto,
    this.onAttachFile,
    this.onSendAttachments,
  });

  final ValueChanged<String>? onSend;
  final MessageItem? replyTo;
  final String replyAuthor;
  final String replyPreview;
  final VoidCallback onCancelReply;

  /// The composer is editing a sent message instead of writing a new one.
  final bool editing;
  final String editPreview;
  final VoidCallback? onCancelEdit;
  final VoidCallback? onAttachPhoto;
  final VoidCallback? onAttachFile;
  final void Function(
    List<ComposerAttachment> attachments,
    String text, {
    int? quotedItemId,
  })?
  onSendAttachments;
  final bool canSend;
  final bool sending;

  @override
  State<_ComposeBar> createState() => _ComposeBarState();
}

class _ComposeBarState extends State<_ComposeBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  /// Pasted media waiting for the send button, like Telegram's send preview.
  final List<ComposerAttachment> _staged = [];

  static const _imageExtensions = [
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
    '.bmp',
  ];

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

  bool get _canSendNow =>
      widget.canSend && (_hasText || _staged.isNotEmpty);

  void _send() {
    if (!_canSendNow) return;
    final text = _controller.text.trim();
    final attachments = List<ComposerAttachment>.of(_staged);
    if (attachments.isNotEmpty) {
      widget.onSendAttachments?.call(attachments, text);
      setState(_staged.clear);
    } else {
      widget.onSend?.call(text);
    }
    _controller.clear();
    _focusNode.requestFocus();
  }

  /// Puts the composer into Telegram's edit mode: the original markdown
  /// source lands in the field with the caret at the end.
  void startEdit(String text) {
    _staged.clear();
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focusNode.requestFocus();
  }

  /// Returns the composer to its normal empty state after an edit.
  void clearComposer() {
    _controller.clear();
    if (_staged.isNotEmpty) setState(_staged.clear);
    _focusNode.requestFocus();
  }

  /// Puts `/command ` at the caret, keeping whatever the user already typed.
  void insertCommand(String command) {
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final before = value.text.substring(0, start);
    final after = value.text.substring(end);
    final prefix = before.isEmpty ||
            before.endsWith(' ') ||
            before.endsWith('\n')
        ? ''
        : ' ';
    final inserted = '$prefix$command ';
    final text = '$before$inserted$after';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + inserted.length),
    );
    _focusNode.requestFocus();
  }

  /// Reads clipboard media the way Telegram's mime-data hook does: local
  /// files first (`HistoryWidget::canSendFiles`), plain text otherwise.
  Future<void> _pasteFromClipboard() async {
    if (!widget.canSend) return;
    // Editing replaces the text of an existing message; clipboard media would
    // silently become a new send instead.
    if (widget.editing) {
      await _pasteText();
      return;
    }
    final payload = await ClipboardFiles.read();
    if (!mounted) return;
    if (payload.isEmpty) {
      await _pasteText();
      return;
    }
    _stageFiles(payload.paths);
  }

  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted) return;
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    _controller.value = TextEditingValue(
      text: value.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _focusNode.requestFocus();
  }

  /// Stages clipboard paths the way Telegram's `PrepareMediaList` does: local
  /// files are read on the spot, and only decodable images become photos.
  void _stageFiles(List<String> paths) {
    final staged = <ComposerAttachment>[];
    for (final path in paths) {
      if (_staged.any((item) => item.path == path) ||
          staged.any((item) => item.path == path)) {
        continue;
      }
      final file = File(path);
      int size;
      try {
        size = file.lengthSync();
      } catch (_) {
        continue;
      }
      final name = path.split(Platform.pathSeparator).last;
      final lowered = name.toLowerCase();
      final looksImage = _imageExtensions.any(lowered.endsWith);
      Uint8List? preview;
      String? previewMime;
      if (looksImage) {
        try {
          final bytes = file.readAsBytesSync();
          // `makePreview` returns the raw bytes for undecodable input, so the
          // decode decides whether this is a photo or a document.
          if (img.decodeImage(bytes) != null) {
            final made = makePreview(bytes);
            preview = made.bytes;
            previewMime = made.mime;
          }
        } catch (_) {
          // Unreadable images stay documents.
        }
      }
      staged.add(
        ComposerAttachment(
          path: path,
          name: name,
          sizeBytes: size,
          isImage: preview != null,
          previewBytes: preview,
          previewMime: previewMime,
        ),
      );
    }
    if (staged.isEmpty || !mounted) return;
    setState(() => _staged.addAll(staged));
    _focusNode.requestFocus();
  }

  void _removeStaged(int index) {
    if (index < 0 || index >= _staged.length) return;
    setState(() => _staged.removeAt(index));
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

  Future<void> _pickAttachment() async {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin = box == null
        ? Offset.zero
        : box.localToGlobal(Offset(0, -8));
    final picked = await showMenu<_AttachAction>(
      context: context,
      color: p.windowBg,
      position: RelativeRect.fromRect(
        origin & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        if (widget.onAttachPhoto != null)
          PopupMenuItem(
            value: _AttachAction.photo,
            child: Row(
              children: [
                Icon(Icons.image_outlined, size: 18, color: p.icon),
                const SizedBox(width: 10),
                Text('Photo', style: t.message.copyWith(color: p.text)),
              ],
            ),
          ),
        if (widget.onAttachFile != null)
          PopupMenuItem(
            value: _AttachAction.file,
            child: Row(
              children: [
                Icon(Icons.attach_file, size: 18, color: p.icon),
                const SizedBox(width: 10),
                Text('File', style: t.message.copyWith(color: p.text)),
              ],
            ),
          ),
        PopupMenuItem(
          value: _AttachAction.paste,
          child: Row(
            children: [
              Icon(Icons.content_paste, size: 18, color: p.icon),
              const SizedBox(width: 10),
              Text('Paste', style: t.message.copyWith(color: p.text)),
            ],
          ),
        ),
      ],
    );
    switch (picked) {
      case _AttachAction.photo:
        widget.onAttachPhoto?.call();
      case _AttachAction.file:
        widget.onAttachFile?.call();
      case _AttachAction.paste:
        unawaited(_pasteFromClipboard());
      case null:
        break;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if ((keyboard.isControlPressed || keyboard.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      unawaited(_pasteFromClipboard());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && widget.editing) {
      widget.onCancelEdit?.call();
      return KeyEventResult.handled;
    }
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
    final t = theme.typography;

    final sendEnabled = _canSendNow;

    // Telegram desktop geometry: flat field between the 44x46 attach and
    // emoji/send buttons, 9px below the field, 2px from both window edges.
    // (`historyAttach`, `historyComposeField`, `historySendPadding`,
    // `historySendRight` in chat_helpers.style.)
    return Container(
      color: p.composeBg,
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_staged.isNotEmpty)
            _StagedAttachments(items: _staged, onRemove: _removeStaged),
          if (widget.editing)
            _ReplyBar(
              key: const ValueKey('edit-bar'),
              author: 'Edit message',
              text: widget.editPreview,
              cancelTooltip: 'Cancel editing',
              onCancel: widget.onCancelEdit ?? widget.onCancelReply,
            )
          else if (widget.replyTo != null)
            _ReplyBar(
              author: widget.replyAuthor,
              text: widget.replyPreview,
              onCancel: widget.onCancelReply,
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 44,
                height: 46,
                child: IconButton(
                  tooltip: 'Attach',
                  onPressed: widget.canSend && !widget.editing
                      ? _pickAttachment
                      : null,
                  icon: Icon(Icons.attach_file, size: 22),
                  color: p.icon,
                  disabledColor: p.searchHint,
                  splashRadius: 20,
                ),
              ),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 36,
                    maxHeight: 72,
                  ),
                  child: Focus(
                    onKeyEvent: _onKey,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 3,
                      enabled: widget.canSend,
                      style: t.input.copyWith(color: p.text),
                      cursorColor: p.accent,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        border: InputBorder.none,
                        hintText: widget.canSend ? 'Message' : 'Not connected',
                        hintStyle: t.input.copyWith(color: p.searchHint),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                height: 46,
                child: IconButton(
                  tooltip: 'Emoji',
                  onPressed: widget.canSend ? _pickEmoji : null,
                  icon: const Icon(Icons.emoji_emotions_outlined, size: 22),
                  color: p.icon,
                  disabledColor: p.searchHint,
                  splashRadius: 20,
                ),
              ),
              SizedBox(
                width: 44,
                height: 46,
                child: widget.sending
                    ? Padding(
                        padding: const EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: p.accent,
                        ),
                      )
                    : IconButton(
                        tooltip: widget.editing ? 'Save' : 'Send',
                        onPressed: sendEnabled ? _send : null,
                        icon: Icon(
                          widget.editing ? Icons.check : Icons.send,
                          size: 22,
                        ),
                        color: p.accent,
                        disabledColor: p.searchHint,
                        splashRadius: 20,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _AttachAction { photo, file, paste }

/// The composer's send preview: pasted photos and files wait here until the
/// send button fires, matching Telegram's attach preview strip.
class _StagedAttachments extends StatelessWidget {
  const _StagedAttachments({required this.items, required this.onRemove});

  final List<ComposerAttachment> items;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    return Container(
      height: 74,
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final item = items[index];
          final preview = item.previewBytes;
          return SizedBox(
            width: 62,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    key: ValueKey('staged-attachment-$index'),
                    width: 62,
                    height: 62,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: p.windowBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.divider),
                    ),
                    child: item.isImage && preview != null
                        ? Image.memory(
                            preview,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.insert_drive_file_outlined,
                                size: 20,
                                color: p.icon,
                              ),
                              const SizedBox(height: 2),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: t.listTime.copyWith(
                                    color: p.textSecondary,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                Positioned(
                  right: -5,
                  top: -5,
                  child: GestureDetector(
                    key: ValueKey('staged-remove-$index'),
                    onTap: () => onRemove(index),
                    child: Container(
                      width: 19,
                      height: 19,
                      decoration: BoxDecoration(
                        color: p.windowBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.divider),
                      ),
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color: p.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    super.key,
    required this.author,
    required this.text,
    required this.onCancel,
    this.cancelTooltip = 'Cancel reply',
  });

  final String author;
  final String text;
  final VoidCallback onCancel;
  final String cancelTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    return SizedBox(
      height: 49,
      child: Row(
        children: [
          Container(
            width: 2,
            height: 30,
            margin: const EdgeInsets.only(left: 8, right: 10),
            color: p.accent,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.sender.copyWith(color: p.accent),
                ),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.messageMeta.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 49,
            height: 49,
            child: IconButton(
              tooltip: cancelTooltip,
              onPressed: onCancel,
              icon: const Icon(Icons.close, size: 20),
              color: p.icon,
              splashRadius: 20,
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
