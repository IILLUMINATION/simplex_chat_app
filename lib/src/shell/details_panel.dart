import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import 'models.dart';
import 'widgets/peer_avatar.dart';

/// Third column: chat profile, mirroring Telegram's info sidebar.
///
/// Cover metrics come from Telegram Desktop (`info.style`: 108 px cover,
/// 72 px userpic at 19/18, name at 109/32, status at 109/58); the narrow
/// layout centres the userpic the way Telegram Android's profile does.
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

    // The panel is a third column on wide screens only; below the shell's
    // 900 px info breakpoint it is pushed as a full screen, which uses the
    // Telegram Android layout (centred userpic, back arrow).
    final compact = MediaQuery.sizeOf(context).width < 900;
    return ColoredBox(
      color: p.windowBg,
      child: Column(
        children: [
          SizedBox(
            height: theme.metrics.topBarHeight,
            child: Row(
              children: [
                if (compact && onClose != null)
                  _TopBarButton(
                    icon: Icons.arrow_back,
                    tooltip: 'Back',
                    onTap: onClose!,
                  )
                else
                  const SizedBox(width: 12),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    chat.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.listName.copyWith(
                      color: p.text,
                      fontSize: compact ? 18 : 15,
                    ),
                  ),
                ),
                if (onSearch != null)
                  _TopBarButton(
                    icon: Icons.search,
                    tooltip: 'Search messages',
                    onTap: onSearch!,
                  ),
                if (!compact && onClose != null)
                  _TopBarButton(
                    icon: Icons.close,
                    tooltip: 'Close',
                    onTap: onClose!,
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Container(height: 1, color: p.divider),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                compact ? _CompactCover(chat: chat) : _Cover(chat: chat),
                if (chat.bio.isNotEmpty)
                  _InfoLine(
                    label: chat.isGroup ? 'Description' : 'Bio',
                    value: chat.bio,
                  ),
                if (chat.fullName.isNotEmpty && chat.fullName != chat.name)
                  _InfoLine(label: 'Full name', value: chat.fullName),
                if (chat.isGroup && chat.memberCount != null)
                  _InfoLine(
                    label: 'Members',
                    value: '${chat.memberCount}',
                  ),
                if (chat.quantumResistant != null)
                  _InfoLine(
                    label: 'E2E encryption',
                    value: chat.quantumResistant!
                        ? 'Quantum resistant'
                        : 'Standard',
                  ),
                const SizedBox(height: 8),
                Container(height: 1, color: p.divider),
                _NotificationsRow(
                  muted: chat.muted,
                  onToggle: onToggleMute,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Telegram Desktop cover: userpic on the left, name and status to its right.
class _Cover extends StatelessWidget {
  const _Cover({required this.chat});

  final ChatSummary chat;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme.typography;
    final p = context.appTheme.palette;
    return SizedBox(
      height: 108,
      child: Stack(
        children: [
          Positioned(
            left: 19,
            top: 18,
            child: PeerAvatar(
              seed: chat.id,
              title: chat.name,
              size: 72,
              fontSize: 26,
              imageBytes: chat.avatarBytes,
            ),
          ),
          Positioned(
            left: 109,
            top: 32,
            right: 20,
            child: Text(
              chat.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.listName.copyWith(color: p.text, fontSize: 16),
            ),
          ),
          Positioned(
            left: 109,
            top: 58,
            right: 20,
            child: Text(
              _status(chat),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.listTime.copyWith(
                color: p.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Telegram Android cover: centred userpic above the name.
class _CompactCover extends StatelessWidget {
  const _CompactCover({required this.chat});

  final ChatSummary chat;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme.typography;
    final p = context.appTheme.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        children: [
          PeerAvatar(
            seed: chat.id,
            title: chat.name,
            size: 112,
            fontSize: 40,
            imageBytes: chat.avatarBytes,
          ),
          const SizedBox(height: 12),
          Text(
            chat.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.chatTitle.copyWith(color: p.text, fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            _status(chat),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.listPreview.copyWith(
              color: p.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

String _status(ChatSummary chat) {
  if (chat.isGroup) {
    final members = chat.memberCount;
    if (members == null) return 'group';
    return '$members ${members == 1 ? 'member' : 'members'}';
  }
  if (chat.needsAccept) return 'contact request';
  return chat.canSend ? 'connected' : 'connecting…';
}

/// Telegram's `TextWithLabel` info row (`infoProfileLabeledPadding`).
class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme.typography;
    final p = context.appTheme.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(23, 9, 20, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: t.listTime.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: t.listPreview.copyWith(color: p.text, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// Telegram settings-style row with a switch (`Switch` in Android's profile).
class _NotificationsRow extends StatelessWidget {
  const _NotificationsRow({required this.muted, this.onToggle});

  final bool muted;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    return InkWell(
      onTap: onToggle,
      hoverColor: p.windowBgOver,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              Icon(
                muted
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_none,
                size: theme.metrics.iconSize,
                color: p.icon,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Notifications',
                  style: t.listPreview.copyWith(color: p.text, fontSize: 14),
                ),
              ),
              Transform.scale(
                scale: 0.82,
                child: Switch(
                  value: !muted,
                  onChanged: onToggle == null ? null : (_) => onToggle!(),
                  activeThumbColor: p.onAccent,
                  activeTrackColor: p.accent,
                  inactiveThumbColor: p.windowBg,
                  inactiveTrackColor: p.windowBgOver,
                  trackOutlineColor: WidgetStatePropertyAll(p.icon),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBarButton extends StatelessWidget {
  const _TopBarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        hoverColor: theme.palette.windowBgOver,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: theme.metrics.iconSize,
            color: theme.palette.icon,
          ),
        ),
      ),
    );
  }
}
