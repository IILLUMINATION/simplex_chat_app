// TangleX — single-chat screen.
//
// Top app bar with avatar + name, messages list (newest at bottom), compose
// bar pinned to the bottom of the safe area. Per HANDOFF.md § 10, this widget
// is kept thin (<200 lines); state lives in `ChatController`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../localization/app_localizations.dart';
import '../../../providers/persistent_store.dart';
import '../../shared/avatar.dart';
import '../../shared/empty_state.dart';
import 'chat_controller.dart';
import 'widgets/compose_bar.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chat});

  final ChatPreview chat;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollCtrl = ScrollController();
  int _lastMessageCount = 0;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _maybeScrollToBottom(int newCount) {
    if (newCount <= _lastMessageCount) {
      _lastMessageCount = newCount;
      return;
    }
    _lastMessageCount = newCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String? _translateSendError(BuildContext context, String? code) {
    if (code == null) return null;
    final t = AppLocalizations.of(context);
    switch (code) {
      case 'contactNotReady':
        return t.translate('send_error_contact_not_ready');
      case 'contactNotActive':
        return t.translate('send_error_contact_not_active');
      case 'noResponse':
        return t.translate('send_error_no_response');
      case 'parseError':
        return t.translate('send_error_parse');
      default:
        return code;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final t = AppLocalizations.of(context);
    final args = ChatArgs(
      chatRef: widget.chat.chatRef,
      isContact: widget.chat.chatType == 'contact',
    );
    final state = ref.watch(chatControllerProvider(args));
    final controller = ref.read(chatControllerProvider(args).notifier);

    // React to new error codes by surfacing a snackbar.
    ref.listen(chatControllerProvider(args), (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        final msg = _translateSendError(context, next.error) ?? next.error!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    });

    _maybeScrollToBottom(state.messages.length);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            TxAvatar(
              name: widget.chat.displayName,
              image: widget.chat.avatarImage,
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.chat.displayName.isEmpty
                        ? '—'
                        : widget.chat.displayName,
                    style: tt.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.chat.chatType == 'group'
                        ? t.translate('chat_type_group')
                        : t.translate('chat_type_contact'),
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _body(context, state, controller)),
          if (widget.chat.embeddedContactRequestId != null && !state.messagingReady)
            Container(
              padding: const EdgeInsets.all(16),
              color: cs.surfaceContainer,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => controller.rejectRequest(widget.chat.embeddedContactRequestId!),
                      icon: const Icon(Icons.close_rounded, color: Colors.red),
                      label: const Text('Отклонить', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => controller.acceptRequest(widget.chat.embeddedContactRequestId!),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Принять'),
                    ),
                  ),
                ],
              ),
            )
          else
            ComposeBar(
              enabled: state.messagingReady,
              sending: state.sending,
              onSend: controller.sendText,
            ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ChatState state,
    ChatController controller,
  ) {
    final t = AppLocalizations.of(context);
    if (state.loading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.messages.isEmpty) {
      return TxEmptyState(
        icon: Icons.chat_outlined,
        title: t.translate('no_messages_yet'),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.messages.length,
      itemBuilder: (context, index) =>
          MessageBubble(message: state.messages[index]),
    );
  }
}
