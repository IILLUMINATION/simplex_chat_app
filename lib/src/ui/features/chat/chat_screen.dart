// TangleX — Telegram Style Chat Screen

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../localization/app_localizations.dart';
import '../../../providers/persistent_store.dart';
import '../../core/theme/tx_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final theme = context.txTheme;

    final args = ChatArgs(
      chatRef: widget.chat.chatRef,
      isContact: widget.chat.chatType == 'contact',
    );
    final state = ref.watch(chatControllerProvider(args));
    final controller = ref.read(chatControllerProvider(args).notifier);

    _maybeScrollToBottom(state.messages.length);

    final showRequestBanner = widget.chat.embeddedContactRequestId != null &&
        !state.messagingReady;

    return Scaffold(
      backgroundColor: theme.chatBackground,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: theme.chatBackground,
        title: Row(
          children: [
            TxAvatar(
              name: widget.chat.displayName,
              image: widget.chat.avatarImage,
              size: 38,
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
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'был(а) недавно', // Статус Telegram
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Панель закрепленного сообщения (Pinned Bar)
          _PinnedMessageBar(
            title: 'Документация.txt',
            onTap: () {},
          ),

          // 2. Список сообщений с разделителями дат
          Expanded(child: _buildMessageList(context, state)),

          // 3. Панель ввода или кнопки Принять/Отклонить запрос
          if (showRequestBanner)
            _ContactRequestBanner(
              onRequestAction: (accept) async {
                final id = widget.chat.embeddedContactRequestId!;
                if (accept) {
                  await controller.acceptContactRequest(id);
                } else {
                  await controller.rejectContactRequest(id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
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

  Widget _buildMessageList(BuildContext context, ChatState state) {
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

    // Группировка с разделителями дат (21 июля, 22 июля)
    final items = <Widget>[];
    DateTime? lastDate;

    for (final msg in state.messages) {
      if (msg.time != null) {
        final msgDate = DateTime(msg.time!.year, msg.time!.month, msg.time!.day);
        if (lastDate == null || lastDate != msgDate) {
          lastDate = msgDate;
          items.add(_DateDivider(date: msg.time!));
        }
      }
      items.add(MessageBubble(message: msg));
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }
}

/// Закрепленное сообщение вверху
class _PinnedMessageBar extends StatelessWidget {
  const _PinnedMessageBar({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Закреплённое сообщение',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(fontSize: 13, color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.volume_off_rounded, size: 20),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

/// Плашка запроса контакта (Принять / Отклонить)
class _ContactRequestBanner extends StatelessWidget {
  const _ContactRequestBanner({required this.onRequestAction});

  final Function(bool accept) onRequestAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Хочет добавить вас в контакты',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onRequestAction(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                  child: const Text('Отклонить'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => onRequestAction(true),
                  child: const Text('Принять'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Разделитель дат (например: "22 июля")
class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final formatted = DateFormat('d MMMM', 'ru').format(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            formatted,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
