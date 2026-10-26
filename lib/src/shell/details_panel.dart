import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import 'models.dart';
import 'widgets/peer_avatar.dart';

/// Third column: chat profile, mirroring Telegram's right sidebar.
class DetailsPanel extends StatelessWidget {
  const DetailsPanel({
    super.key,
    required this.chat,
    this.onClose,
    this.onToggleMute,
    this.onSearch,
  });

  final ChatSummary chat;
  final VoidCallback? onClose;
  final VoidCallback? onToggleMute;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;

    return ColoredBox(
      color: p.windowBg,
      child: Column(
        children: [
          SizedBox(
            height: theme.metrics.topBarHeight,
            child: Row(
              children: [
                if (onClose != null)
                  IconButton(
                    onPressed: onClose,
                    icon: Icon(Icons.close, size: theme.metrics.iconSize),
                    color: p.icon,
                  ),
                const SizedBox(width: 8),
                Text('Profile', style: t.chatTitle.copyWith(color: p.text)),
              ],
            ),
          ),
          Container(height: 1, color: p.divider),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              children: [
                const SizedBox(height: 12),
                Center(
                  child: PeerAvatar(
                    seed: chat.id,
                    title: chat.name,
                    size: 100,
                    fontSize: 36,
                    imageBytes: chat.avatarBytes,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    chat.name,
                    textAlign: TextAlign.center,
                    style: t.chatTitle.copyWith(color: p.text, fontSize: 17),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    chat.subtitle ??
                        (chat.online ? 'online' : 'last seen recently'),
                    style: t.listTime.copyWith(
                      color: chat.online ? p.link : p.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (onToggleMute != null || onSearch != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (onToggleMute != null)
                        _Action(
                          icon: chat.muted
                              ? Icons.volume_off
                              : Icons.volume_up,
                          label: chat.muted ? 'Unmute' : 'Mute',
                          onTap: onToggleMute!,
                        ),
                      if (onSearch != null)
                        _Action(
                          icon: Icons.search,
                          label: 'Search',
                          onTap: onSearch!,
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                Container(height: 1, color: p.divider),
                _InfoTile(
                  icon: chat.isGroup
                      ? Icons.groups_outlined
                      : Icons.person_outline,
                  title: chat.isGroup ? 'Group chat' : 'Direct chat',
                  subtitle: 'Chat type',
                ),
                _InfoTile(
                  icon: chat.canSend
                      ? Icons.check_circle_outline
                      : Icons.schedule,
                  title: chat.canSend ? 'Ready to send' : 'Connecting…',
                  subtitle: 'Connection',
                ),
                _InfoTile(
                  icon: Icons.tag,
                  title: chat.id,
                  subtitle: 'SimpleX chat reference',
                ),
                if (chat.unread > 0)
                  _InfoTile(
                    icon: Icons.mark_chat_unread_outlined,
                    title: '${chat.unread} unread',
                    subtitle: 'Unread messages',
                  ),
                if (chat.muted)
                  const _InfoTile(
                    icon: Icons.notifications_off_outlined,
                    title: 'Notifications off',
                    subtitle: 'Muted',
                  ),
                if (chat.pinned)
                  const _InfoTile(
                    icon: Icons.push_pin_outlined,
                    title: 'Pinned',
                    subtitle: 'Shown at the top of the list',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: p.windowBgOver,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            Icon(icon, size: theme.metrics.iconSize, color: p.iconActive),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.typography.listTime.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Icon(icon, size: theme.metrics.iconSize, color: p.icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.listPreview.copyWith(
                    color: p.text,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.typography.listTime.copyWith(
                    color: p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
