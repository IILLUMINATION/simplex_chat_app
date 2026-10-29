import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/account_providers.dart';
import '../data/chat_core.dart';
import '../data/chat_providers.dart';
import '../design/app_theme.dart';
import '../ui/chat/utils/chat_message_parser.dart';
import 'adaptive_shell.dart';
import 'appearance_settings.dart';
import 'chat_list_panel.dart';
import 'contacts_screen.dart';
import 'conversation_panel.dart';
import 'details_panel.dart';
import 'main_menu.dart';
import 'models.dart';
import 'profile_screen.dart';

/// Top-level messenger: three adaptive columns fed by the SimpleX core.
class MessengerShell extends ConsumerStatefulWidget {
  const MessengerShell({super.key});

  @override
  ConsumerState<MessengerShell> createState() => _MessengerShellState();
}

class _MessengerShellState extends ConsumerState<MessengerShell> {
  String? _selectedId;
  bool _detailsOpen = false;
  bool _autoSelectScheduled = false;

  void _maybeAutoSelect(List<ChatSummary> chats) {
    if (_selectedId != null || _autoSelectScheduled || chats.isEmpty) return;
    if (MediaQuery.sizeOf(context).width < 640) return;
    _autoSelectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSelectScheduled = false;
      if (!mounted || _selectedId != null) return;
      _select(chats.first.id);
    });
  }

  /// Drops a selection that no longer exists (profile switch, chat deleted).
  void _syncSelection(List<ChatSummary> chats) {
    final selectedId = _selectedId;
    if (selectedId != null &&
        !chats.any((chat) => chat.id == selectedId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedId != selectedId) return;
        setState(() {
          _selectedId = null;
          _detailsOpen = false;
        });
        ref.read(activeChatRefProvider.notifier).state = null;
      });
      return;
    }
    _maybeAutoSelect(chats);
  }

  Future<void> _select(String id) async {
    if (_selectedId != id) {
      setState(() {
        _selectedId = id;
        _detailsOpen = false;
      });
    }
    ref.read(activeChatRefProvider.notifier).state = id;
    final chats = ref.read(chatsProvider).valueOrNull ?? const <ChatSummary>[];
    ChatSummary? chat;
    for (final candidate in chats) {
      if (candidate.id == id) chat = candidate;
    }
    if (chat == null || chat.unread <= 0) return;
    await ref.read(chatCoreProvider).markRead(id);
    await ref.read(chatsProvider.notifier).refresh();
  }

  void _openAppearance() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AppearanceScreenHost()),
    );
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const OwnProfileScreen()),
    );
  }

  void _openContacts() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContactsScreen(onOpenChat: _select),
      ),
    );
  }

  Future<void> _openNewChat() async {
    final chats = ref.read(chatsProvider).valueOrNull ?? const <ChatSummary>[];
    await showNewChatDialog(
      context,
      contacts: chats.where((chat) => !chat.isGroup).toList(),
      onOpenChat: _select,
    );
  }

  void _openMenu() {
    showMainMenu(
      context,
      compact: MediaQuery.sizeOf(context).width < 640,
      onProfile: _openProfile,
      onNewChat: _openNewChat,
      onContacts: _openContacts,
      onAppearance: _openAppearance,
    );
  }

  Future<void> _toggleMute(ChatSummary chat) async {
    final ok = await ref
        .read(chatsProvider.notifier)
        .setMuted(chat.id, muted: !chat.muted);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not change notifications'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _attachPhoto(String chatRef) async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 90);
    if (files.isEmpty || !mounted) return;
    final images = <OutgoingImage>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final preview = makePreview(bytes);
      images.add(
        OutgoingImage(
          filePath: file.path,
          previewBytes: preview.bytes,
          previewMime: preview.mime,
        ),
      );
    }
    final ok = await ref
        .read(chatCoreProvider)
        .sendImages(chatRef, images);
    if (!ok) _toast('Could not send the photo');
  }

  Future<void> _attachFile(String chatRef) async {
    final result = await FilePicker.platform.pickFiles(
      withData: false,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    var failed = false;
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      final ok = await ref.read(chatCoreProvider).sendFile(chatRef, path);
      failed = failed || !ok;
    }
    if (failed) _toast('Could not send the file');
  }

  /// Sends the composer's pasted attachments. Photos leave as one album with
  /// the caption on its first photo, documents follow as file messages, so
  /// the caption lands on exactly the first item like Telegram's send preview.
  Future<void> _sendAttachments(
    String chatRef,
    List<ComposerAttachment> attachments,
    String caption, {
    int? quotedItemId,
  }) async {
    if (attachments.isEmpty) return;
    final images = <OutgoingImage>[];
    final files = <ComposerAttachment>[];
    for (final attachment in attachments) {
      final preview = attachment.previewBytes;
      if (attachment.isImage && preview != null) {
        images.add(
          OutgoingImage(
            filePath: attachment.path,
            previewBytes: preview,
            previewMime: attachment.previewMime ?? 'image/jpeg',
          ),
        );
      } else {
        files.add(attachment);
      }
    }
    var failed = false;
    var captionPending = caption.isNotEmpty;
    var quotePending = quotedItemId != null;
    if (images.isNotEmpty) {
      final ok = await ref
          .read(chatCoreProvider)
          .sendImages(
            chatRef,
            images,
            text: captionPending ? caption : '',
            quotedItemId: quotePending ? quotedItemId : null,
          );
      failed = !ok;
      captionPending = false;
      quotePending = false;
    }
    for (final file in files) {
      final ok = await ref
          .read(chatCoreProvider)
          .sendFile(
            chatRef,
            file.path,
            text: captionPending ? caption : '',
            quotedItemId: quotePending ? quotedItemId : null,
          );
      failed = failed || !ok;
      captionPending = false;
      quotePending = false;
    }
    if (failed && mounted) _toast('Could not send the attachment');
  }

  Future<void> _downloadFile(MessageItem message) async {
    final fileId = message.fileId;
    if (fileId == null) return;
    final ok = await ref.read(chatCoreProvider).receiveFile(fileId);
    if (!ok) _toast('Could not download the file');
  }

  Future<void> _openFile(MessageItem message) async {
    final path = message.filePath;
    if (path == null || path.isEmpty) return;
    try {
      if (Platform.isLinux) {
        await Process.start(
          'xdg-open',
          [path],
          mode: ProcessStartMode.detached,
        );
      } else if (Platform.isMacOS) {
        await Process.start('open', [path], mode: ProcessStartMode.detached);
      } else if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', path]);
      }
    } catch (_) {
      _toast('Could not open the file');
    }
  }

  void _toggleReaction(MessageItem message, String emoji) {
    final itemId = message.itemId;
    if (itemId == null || _selectedId == null) return;
    ref
        .read(messagesProvider(_selectedId!).notifier)
        .toggleReaction(itemId, emoji);
  }

  /// The core copies the item into the target chat; both chat lists pick the
  /// change up from `newChatItems`, so only the toast is ours.
  Future<void> _forwardMessage(
    String fromChatRef,
    int itemId,
    ChatSummary target,
  ) async {
    final ok = await ref
        .read(chatCoreProvider)
        .forwardMessages(target.id, fromChatRef, [itemId]);
    if (!mounted) return;
    _toast(ok ? 'Forwarded to ${target.name}' : 'Could not forward the message');
  }

  Future<void> _acceptRequest(int requestId, {bool incognito = false}) async {
    final ok = await ref
        .read(chatCoreProvider)
        .acceptContactRequest(requestId, incognito: incognito);
    if (!ok) {
      _toast('Could not accept the contact request');
      return;
    }
    await ref.read(chatsProvider.notifier).refresh();
  }

  Future<void> _declineRequest(ChatSummary chat) async {
    final requestId = chat.requestId;
    if (requestId == null) return;
    final ok = await ref
        .read(chatCoreProvider)
        .rejectContactRequest(requestId);
    if (!ok) {
      _toast('Could not decline the contact request');
      return;
    }
    await ref.read(chatsProvider.notifier).refresh();
  }

  /// Telegram opens the profile from the conversation header: third column on
  /// desktop, a pushed screen on tablet/phone.
  void _openInfo(ChatSummary chat) {
    if (MediaQuery.sizeOf(context).width >= 900) {
      setState(() => _detailsOpen = true);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          backgroundColor: context.appTheme.palette.windowBg,
          body: DetailsPanel(
            chat: chat,
            onClose: () => Navigator.of(routeContext).pop(),
            onToggleMute: () => _toggleMute(chat),
            onSearch: () {
              Navigator.of(routeContext).pop();
              ref.read(chatSearchRequestProvider(chat.id).notifier).state++;
            },
          ),
        ),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _createFirstProfile() async {
    final draft = await showProfileEditDialog(
      context,
      title: 'Create profile',
      submitLabel: 'Create',
      description:
          'This name and bio are shown to the people you chat with. '
          'You can add more profiles later.',
    );
    if (draft == null || !mounted) return;
    final account = await ref
        .read(accountsProvider.notifier)
        .create(
          displayName: draft.displayName,
          fullName: draft.fullName,
          shortDescr: draft.shortDescr,
        );
    if (!mounted) return;
    _toast(
      account == null
          ? 'Could not create a profile'
          : 'Welcome to TangleX, ${account.displayName}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final accounts = ref.watch(accountsProvider).valueOrNull;
    if (accounts != null && accounts.accounts.isEmpty) {
      return Scaffold(
        backgroundColor: theme.palette.windowBg,
        body: _WelcomePane(onCreateProfile: _createFirstProfile),
      );
    }
    final chatsAsync = ref.watch(chatsProvider);
    final chats = chatsAsync.valueOrNull ?? const <ChatSummary>[];
    _syncSelection(chats);

    ChatSummary? selected;
    for (final chat in chats) {
      if (chat.id == _selectedId) selected = chat;
    }

    final chatList = switch (chatsAsync) {
      AsyncError(:final error) when chats.isEmpty => _StatusPane(
        icon: Icons.cloud_off,
        title: 'Core is not available',
        detail: '$error',
        onRetry: () => ref.invalidate(coreReadyProvider),
      ),
      AsyncLoading() when chats.isEmpty => const _StatusPane(
        icon: Icons.hourglass_empty,
        title: 'Connecting to the core…',
      ),
      _ => ChatListPanel(
        chats: chats,
        selectedId: _selectedId,
        onSelect: _select,
        onOpenMenu: _openMenu,
        onCompose: _openNewChat,
        onAppearance: _openAppearance,
      ),
    };

    Widget conversation = const EmptyConversation();
    final selectedChat = selected;
    if (selectedChat != null) {
      final messagesAsync = ref.watch(messagesProvider(selectedChat.id));
      final messages = messagesAsync.valueOrNull ?? const <MessageItem>[];
      final sending = messages.any(
        (m) => m.outgoing && m.status == MessageStatus.sending,
      );
      conversation = ConversationPanel(
        key: ValueKey(selectedChat.id),
        chat: selectedChat,
        messages: messages,
        loading: messagesAsync.isLoading && messages.isEmpty,
        canSend: selectedChat.canSend,
        sending: sending,
        searchRequest: ref.watch(chatSearchRequestProvider(selectedChat.id)),
        onSend: (text, {int? quotedItemId, MessageReply? reply}) => ref
            .read(messagesProvider(selectedChat.id).notifier)
            .send(
              text,
              quotedItemId: quotedItemId,
              reply: reply,
            ),
        onReact: _toggleReaction,
        onEdit: (message, text) {
          final itemId = message.itemId;
          if (itemId == null) return;
          ref
              .read(messagesProvider(selectedChat.id).notifier)
              .editMessage(itemId, text);
        },
        onDelete: (message, {required bool forEveryone}) {
          final itemId = message.itemId;
          if (itemId == null) return;
          ref
              .read(messagesProvider(selectedChat.id).notifier)
              .deleteMessage(itemId, forEveryone: forEveryone);
        },
        forwardTargets: chats,
        onForward: (message, target) {
          final itemId = message.itemId;
          if (itemId == null) return;
          _forwardMessage(selectedChat.id, itemId, target);
        },
        onAttachPhoto: () => _attachPhoto(selectedChat.id),
        onAttachFile: () => _attachFile(selectedChat.id),
        onSendAttachments: (attachments, caption, {int? quotedItemId}) =>
            _sendAttachments(
              selectedChat.id,
              attachments,
              caption,
              quotedItemId: quotedItemId,
            ),
        onDownloadFile: _downloadFile,
        onOpenFile: _openFile,
        onAcceptRequest: _acceptRequest,
        onDeclineRequest: () => _declineRequest(selectedChat),
        onBack: MediaQuery.sizeOf(context).width < 640
            ? () => setState(() => _selectedId = null)
            : null,
        onOpenInfo: () => _openInfo(selectedChat),
      );
    }

    return Scaffold(
      backgroundColor: theme.palette.windowBg,
      body: AdaptiveShell(
        chatSelected: selected != null,
        detailsOpen: _detailsOpen,
        chatList: chatList,
        conversation: conversation,
        emptyConversation: const EmptyConversation(),
        details: selected == null
            ? null
            : DetailsPanel(
                chat: selected,
                onClose: () => setState(() => _detailsOpen = false),
                onToggleMute: () => _toggleMute(selected!),
                onSearch: () => ref
                    .read(chatSearchRequestProvider(selected!.id).notifier)
                    .state++,
              ),
      ),
    );
  }
}

class _WelcomePane extends StatelessWidget {
  const _WelcomePane({required this.onCreateProfile});

  final VoidCallback onCreateProfile;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: p.accent,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.forum_outlined, size: 44, color: p.onAccent),
            ),
            const SizedBox(height: 20),
            Text(
              'Welcome to TangleX',
              textAlign: TextAlign.center,
              style: t.chatTitle.copyWith(color: p.text, fontSize: 22),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                'Create a profile to start messaging over SimpleX. '
                'Each profile is a separate identity with its own chats.',
                textAlign: TextAlign.center,
                style: t.listPreview.copyWith(color: p.textSecondary),
              ),
            ),
            const SizedBox(height: 22),
            Material(
              color: p.accent,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onCreateProfile,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 11,
                  ),
                  child: Text(
                    'Create profile',
                    style: t.button.copyWith(color: p.onAccent),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPane extends StatelessWidget {  const _StatusPane({
    required this.icon,
    required this.title,
    this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return ColoredBox(
      color: p.windowBg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: p.icon),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.typography.listName.copyWith(color: p.text),
              ),
              if (detail != null) ...[
                const SizedBox(height: 6),
                Text(
                  detail!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.typography.listPreview.copyWith(
                    color: p.textSecondary,
                  ),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 14),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
