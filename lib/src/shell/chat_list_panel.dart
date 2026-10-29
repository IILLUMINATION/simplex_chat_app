import 'package:flutter/material.dart';

import '../design/app_metrics.dart';
import '../design/app_theme.dart';
import 'adaptive_shell.dart';
import 'models.dart';
import 'widgets/peer_avatar.dart';

class ChatListPanel extends StatefulWidget {
  const ChatListPanel({
    super.key,
    required this.chats,
    required this.selectedId,
    required this.onSelect,
    this.onOpenMenu,
    this.onCompose,
    this.onAppearance,
  });

  final List<ChatSummary> chats;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onCompose;
  final VoidCallback? onAppearance;

  @override
  State<ChatListPanel> createState() => _ChatListPanelState();
}

class _ChatListPanelState extends State<ChatListPanel> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final m = theme.metrics;

    final query = _searchController.text.trim().toLowerCase();
    final matching = query.isEmpty
        ? widget.chats
        : widget.chats
              .where(
                (c) =>
                    c.name.toLowerCase().contains(query) ||
                    c.preview.toLowerCase().contains(query),
              )
              .toList();
    // Pending contact requests are surfaced above the regular chats, like
    // Telegram's message requests folder.
    final requests = matching.where((c) => c.needsAccept).toList();
    final chats = [
      ...requests,
      ...matching.where((c) => !c.needsAccept),
    ];
    final headerCount = requests.isEmpty ? 0 : 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Telegram paints dialog rows without their text once the column is
        // narrower than half of the minimal left column, and the shell snaps
        // the width to the avatar rail there.
        if (constraints.maxWidth < m.leftColumnMin / 2) {
          return _CompactChatList(
            chats: chats,
            selectedId: widget.selectedId,
            onSelect: widget.onSelect,
            onOpenMenu: widget.onOpenMenu,
          );
        }
        return ColoredBox(
          color: p.windowBg,
          child: Column(
            children: [
              SizedBox(
                height: m.topBarHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'TangleX',
                          style: theme.typography.chatTitle.copyWith(
                            color: p.text,
                          ),
                        ),
                      ),
                      _BarIcon(
                        icon: Icons.edit_outlined,
                        onTap: widget.onCompose,
                      ),
                      _BarIcon(
                        icon: Icons.palette_outlined,
                        onTap: widget.onAppearance,
                      ),
                      _BarIcon(icon: Icons.menu, onTap: widget.onOpenMenu),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.searchBg,
                    borderRadius: BorderRadius.circular(m.searchRadius),
                  ),
                  child: SizedBox(
                    height: m.searchHeight,
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        Icon(
                          Icons.search,
                          size: m.iconSize * 0.85,
                          color: p.searchHint,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (_) => setState(() {}),
                            style: theme.typography.input.copyWith(
                              color: p.text,
                            ),
                            cursorColor: p.accent,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Search',
                              hintStyle: theme.typography.input.copyWith(
                                color: p.searchHint,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: chats.isEmpty
                    ? Center(
                        child: Text(
                          query.isEmpty ? 'No chats yet' : 'No results',
                          style: theme.typography.listPreview.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: chats.length + headerCount,
                        itemBuilder: (context, index) {
                          if (headerCount == 1 && index == 0) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                              child: Text(
                                'CONTACT REQUESTS',
                                style: theme.typography.listTime.copyWith(
                                  color: p.textSecondary,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            );
                          }
                          final chat = chats[index - headerCount];
                          return _ChatRow(
                            chat: chat,
                            selected: chat.id == widget.selectedId,
                            onTap: () => widget.onSelect(chat.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Telegram's compact dialogs column: the menu and search buttons are
/// centered above an avatar-only list (`dialogsSmallColumnWidth`).
class _CompactChatList extends StatelessWidget {
  const _CompactChatList({
    required this.chats,
    required this.selectedId,
    required this.onSelect,
    required this.onOpenMenu,
  });

  final List<ChatSummary> chats;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback? onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final m = theme.metrics;
    final expand = ChatListLayout.maybeOf(context)?.expand;

    return ColoredBox(
      color: p.windowBg,
      child: Column(
        children: [
          SizedBox(
            height: m.topBarHeight,
            child: Center(
              child: _BarIcon(icon: Icons.menu, onTap: onOpenMenu),
            ),
          ),
          SizedBox(
            height: 40,
            child: Center(
              child: _BarIcon(
                icon: Icons.search,
                onTap: expand,
              ),
            ),
          ),
          Expanded(
            child: chats.isEmpty
                ? Center(
                    child: Icon(
                      Icons.forum_outlined,
                      size: m.iconSize,
                      color: p.searchHint,
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: chats.length,
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      return _CompactChatRow(
                        chat: chat,
                        selected: chat.id == selectedId,
                        onTap: () => onSelect(chat.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CompactChatRow extends StatelessWidget {
  const _CompactChatRow({
    required this.chat,
    required this.selected,
    required this.onTap,
  });

  final ChatSummary chat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final m = theme.metrics;
    return Tooltip(
      message: chat.name,
      waitDuration: const Duration(milliseconds: 400),
      child: _HoverSurface(
        color: selected ? p.listRowSelected : p.listRowHover,
        active: selected,
        onTap: onTap,
        child: SizedBox(
          height: m.listRowHeight,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PeerAvatar(
                  seed: chat.id,
                  title: chat.name,
                  size: m.avatarSize,
                  online: chat.online,
                  imageBytes: chat.avatarBytes,
                ),
                if (chat.unread > 0)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: chat.muted ? p.badgeMuted : p.badge,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: p.windowBg, width: 1.5),
                      ),
                      child: Text(
                        '${chat.unread}',
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
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return _HoverSurface(
      color: theme.palette.windowBgOver,
      radius: 18,
      onTap: onTap,
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

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.chat,
    required this.selected,
    required this.onTap,
  });

  final ChatSummary chat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final m = theme.metrics;
    final t = theme.typography;

    final nameColor = selected ? p.listNameSelected : p.listName;
    final previewColor = selected ? p.listNameSelected : p.listPreview;
    final timeColor = selected ? p.listNameSelected : p.listDate;
    final senderColor = selected ? p.listNameSelected : p.listSender;

    return _HoverSurface(
      color: selected ? p.listRowSelected : p.listRowHover,
      active: selected,
      onTap: onTap,
      child: SizedBox(
        height: m.listRowHeight,
        child: Padding(
          padding: m.listPadding,
          child: Row(
            children: [
              PeerAvatar(
                seed: chat.id,
                title: chat.name,
                size: m.avatarSize,
                online: chat.online,
                imageBytes: chat.avatarBytes,
              ),
              SizedBox(width: m.avatarTextGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  chat.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.listName.copyWith(color: nameColor),
                                ),
                              ),
                              if (chat.verified) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.verified,
                                  size: 14,
                                  color: senderColor,
                                ),
                              ],
                              if (chat.muted) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.volume_off,
                                  size: 14,
                                  color: timeColor.withValues(alpha: 0.8),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (chat.pinned)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.push_pin,
                              size: 14,
                              color: timeColor.withValues(alpha: 0.8),
                            ),
                          ),
                        Text(
                          chat.time,
                          style: t.listTime.copyWith(color: timeColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: chat.needsAccept
                                  ? [
                                      TextSpan(
                                        text: 'Contact request',
                                        style: t.listPreview.copyWith(
                                          color: selected
                                              ? p.listNameSelected
                                              : p.accent,
                                        ),
                                      ),
                                    ]
                                  : [
                                      if (chat.previewAuthor != null)
                                        TextSpan(
                                          text: '${chat.previewAuthor}: ',
                                          style: t.listPreview.copyWith(
                                            color: senderColor,
                                          ),
                                        ),
                                      TextSpan(
                                        text: chat.preview,
                                        style: t.listPreview.copyWith(
                                          color: previewColor,
                                        ),
                                      ),
                                    ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (chat.unread > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            height: m.badgeHeight,
                            padding: m.badgePadding,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? p.listNameSelected
                                  : (chat.muted ? p.badgeMuted : p.badge),
                              borderRadius: BorderRadius.circular(
                                m.badgeHeight / 2,
                              ),
                            ),
                            child: Text(
                              '${chat.unread}',
                              style: t.badge.copyWith(
                                color: selected
                                    ? p.listRowSelected
                                    : p.badgeText,
                              ),
                            ),
                          ),
                        ],
                      ],
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

/// Hover/pressed surface with Telegram-like feedback: instant color on hover,
/// no ripple.
class _HoverSurface extends StatefulWidget {
  const _HoverSurface({
    required this.child,
    required this.color,
    this.onTap,
    this.radius = 0,
    this.active = false,
  });

  final Widget child;
  final Color color;
  final VoidCallback? onTap;
  final double radius;
  final bool active;

  @override
  State<_HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<_HoverSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: theme.motion.universal,
          curve: AppMotion.ease,
          decoration: BoxDecoration(
            color: (widget.active || _hovered)
                ? widget.color
                : Colors.transparent,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
