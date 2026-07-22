// TangleX — chats list screen.
//
// Material 3 ListView of chats. Each row is a ListTile with a tonal avatar,
// display name, last-message preview and an unread badge. Tapping a contact
// row opens the chat screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../localization/app_localizations.dart';
import '../../../providers/persistent_store.dart';
import '../../shared/avatar.dart';
import '../../shared/empty_state.dart';
import '../chat/chat_screen.dart';
import 'chats_controller.dart';

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatsControllerProvider);
    final t = AppLocalizations.of(context);

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(chatsControllerProvider.notifier).refresh(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar.medium(
            title: Text(t.translate('chats')),
            pinned: true,
          ),
          if (state.loading && state.chats.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.chats.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: TxEmptyState(
                icon: Icons.forum_outlined,
                title: t.translate('no_chats_yet'),
                subtitle: t.translate('tap_add_chat'),
              ),
            )
          else
            SliverList.separated(
              itemCount: state.chats.length,
              separatorBuilder: (_, _) => Divider(
                indent: 76,
                endIndent: 16,
                height: 0,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              itemBuilder: (context, index) =>
                  _ChatRow(chat: state.chats[index]),
            ),
        ],
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat});

  final ChatPreview chat;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final t = AppLocalizations.of(context);
    final showSubtitle = chat.lastMessage.isNotEmpty;
    final canOpen = chat.chatType == 'contact' || chat.chatType == 'group' || chat.chatType == 'contactRequest';

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: TxAvatar(
        name: chat.displayName,
        image: chat.avatarImage,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              chat.displayName.isEmpty ? '—' : chat.displayName,
              style: tt.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (chat.timestamp != null)
            Text(
              _formatTime(chat.timestamp!),
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
      subtitle: showSubtitle
          ? Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  if (chat.lastFromMe)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '${t.translate('you_label')}:',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      chat.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (chat.unreadCount > 0) ...[
                    const SizedBox(width: 8),
                    _UnreadBadge(count: chat.unreadCount),
                  ],
                ],
              ),
            )
          : (chat.needsAcceptFromDirectRow || chat.isConnectingWithoutRequest)
              ? Text(
                  t.translate('pending_acceptance'),
                  style: tt.bodySmall?.copyWith(
                    color: cs.tertiary,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : null,
      onTap: canOpen
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(chat: chat),
                ),
              );
            }
          : null,
    );
  }

  static String _formatTime(int microSeconds) {
    final dt = DateTime.fromMicrosecondsSinceEpoch(microSeconds).toLocal();
    final now = DateTime.now();
    final isSameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isSameDay) return DateFormat('HH:mm').format(dt);
    final daysAgo = now.difference(dt).inDays;
    if (daysAgo < 7) return DateFormat('EEE').format(dt);
    return DateFormat('dd.MM').format(dt);
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: tt.labelSmall?.copyWith(
          color: cs.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
