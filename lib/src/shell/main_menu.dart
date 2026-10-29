import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_models.dart';
import '../data/profile_image.dart';
import '../data/account_providers.dart';
import '../design/app_theme.dart';
import '../design/app_theme_controller.dart';
import 'profile_screen.dart';
import 'widgets/peer_avatar.dart';

typedef MenuAction = VoidCallback;

/// Telegram-style side menu: a drawer on phones, an anchored dropdown panel on
/// desktop. Profile header, account switcher, navigation and night mode.
Future<void> showMainMenu(
  BuildContext context, {
  required bool compact,
  required MenuAction onProfile,
  required MenuAction onNewChat,
  required MenuAction onContacts,
  required MenuAction onAppearance,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Main menu',
    barrierColor: compact ? const Color(0x66000000) : const Color(0x1A000000),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => _MainMenuOverlay(
      compact: compact,
      onProfile: onProfile,
      onNewChat: onNewChat,
      onContacts: onContacts,
      onAppearance: onAppearance,
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-0.04, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _MainMenuOverlay extends StatelessWidget {
  const _MainMenuOverlay({
    required this.compact,
    required this.onProfile,
    required this.onNewChat,
    required this.onContacts,
    required this.onAppearance,
  });

  final bool compact;
  final MenuAction onProfile;
  final MenuAction onNewChat;
  final MenuAction onContacts;
  final MenuAction onAppearance;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final size = MediaQuery.sizeOf(context);
    final width = compact ? math.min(size.width * 0.86, 340.0) : 320.0;
    final maxHeight = compact
        ? size.height
        : math.min(size.height - 24, 640.0);

    final panel = _MainMenuPanel(
      compact: compact,
      onProfile: onProfile,
      onNewChat: onNewChat,
      onContacts: onContacts,
      onAppearance: onAppearance,
    );

    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: compact ? EdgeInsets.zero : const EdgeInsets.all(12),
        child: Material(
          color: p.windowBg,
          elevation: compact ? 0 : 14,
          shadowColor: const Color(0x66000000),
          borderRadius: compact ? BorderRadius.zero : BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: compact ? size.height : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: panel,
            ),
          ),
        ),
      ),
    );
  }
}

class _MainMenuPanel extends ConsumerWidget {
  const _MainMenuPanel({
    required this.compact,
    required this.onProfile,
    required this.onNewChat,
    required this.onContacts,
    required this.onAppearance,
  });

  final bool compact;
  final MenuAction onProfile;
  final MenuAction onNewChat;
  final MenuAction onContacts;
  final MenuAction onAppearance;

  Future<void> _switchTo(
    BuildContext context,
    WidgetRef ref,
    AccountProfile account,
  ) async {
    if (account.active) return;
    final ok = await ref
        .read(accountsProvider.notifier)
        .switchTo(account.userId);
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not switch profile'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _createProfile(BuildContext context, WidgetRef ref) async {
    final draft = await showProfileEditDialog(
      context,
      title: 'New profile',
      submitLabel: 'Create',
      description:
          'A profile is a separate SimpleX user on this device. '
          'Each one has its own chats and address.',
    );
    if (draft == null || !context.mounted) return;
    final account = await ref
        .read(accountsProvider.notifier)
        .create(
          displayName: draft.displayName,
          fullName: draft.fullName,
          shortDescr: draft.shortDescr,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          account == null
              ? 'Could not create a profile'
              : 'Profile “${account.displayName}” created',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _closeThen(BuildContext context, MenuAction action) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    final accountsAsync = ref.watch(accountsProvider);
    final accounts = accountsAsync.valueOrNull ?? const AccountsState();
    final active = accounts.active;
    final mode = ref.watch(appThemeProvider).mode;
    final dark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };

    return SafeArea(
      child: Column(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Flexible(
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: !compact,
              children: [
                _ProfileHeader(
                  account: active,
                  onTap: active == null
                      ? () => _createProfile(context, ref)
                      : () => _closeThen(context, onProfile),
                ),
                Container(height: 1, color: p.divider),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Text(
                    'ACCOUNTS',
                    style: t.sectionHeader.copyWith(
                      color: p.textSecondary,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                for (final account in accounts.accounts)
                  _AccountRow(
                    account: account,
                    onTap: () => _switchTo(context, ref, account),
                  ),
                _MenuRow(
                  icon: Icons.add_circle_outline,
                  label: 'Add profile',
                  onTap: () => _createProfile(context, ref),
                  accent: true,
                ),
                const SizedBox(height: 4),
                Container(height: 1, color: p.divider),
                _MenuRow(
                  icon: Icons.edit_outlined,
                  label: 'New chat',
                  onTap: () => _closeThen(context, onNewChat),
                ),
                _MenuRow(
                  icon: Icons.people_outline,
                  label: 'Contacts',
                  onTap: () => _closeThen(context, onContacts),
                ),
                _MenuRow(
                  icon: Icons.palette_outlined,
                  label: 'Appearance',
                  onTap: () => _closeThen(context, onAppearance),
                ),
                _MenuRow(
                  icon: Icons.dark_mode_outlined,
                  label: 'Night mode',
                  trailing: IgnorePointer(
                    child: Switch(
                      value: dark,
                      onChanged: (_) {},
                      activeThumbColor: Colors.white,
                      activeTrackColor: p.accent,
                      inactiveThumbColor: p.textSecondary,
                      inactiveTrackColor: p.windowBgOver,
                      trackOutlineColor: WidgetStatePropertyAll(p.divider),
                    ),
                  ),
                  onTap: () => ref
                      .read(appThemeProvider.notifier)
                      .setMode(dark ? ThemeMode.light : ThemeMode.dark),
                ),
              ],
            ),
          ),
          Container(height: 1, color: p.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'TangleX',
                    style: t.listName.copyWith(color: p.text),
                  ),
                ),
                Text(
                  compact ? 'SimpleX core' : 'SimpleX core · desktop',
                  style: t.listTime.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.account, required this.onTap});

  final AccountProfile? account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    final name = account?.displayName ?? 'My profile';
    final subtitle = account == null
        ? 'Set up your SimpleX profile'
        : (account!.fullName.isNotEmpty
              ? account!.fullName
              : (account!.localDisplayName.isNotEmpty
                    ? '@${account!.localDisplayName}'
                    : 'SimpleX profile'));

    return InkWell(
      onTap: onTap,
      hoverColor: p.windowBgOver,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 12, 16),
        child: Row(
          children: [
            PeerAvatar(
              seed: account == null ? 'anonymous' : 'user-${account!.userId}',
              title: name,
              size: 54,
              imageBytes: profileImageBytes(account?.image),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.listName.copyWith(color: p.text, fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.listTime.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: p.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.onTap});

  final AccountProfile account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    return InkWell(
      onTap: onTap,
      hoverColor: p.windowBgOver,
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              PeerAvatar(
                seed: 'user-${account.userId}',
                title: account.displayName,
                size: 26,
                imageBytes: profileImageBytes(account.image),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.listPreview.copyWith(color: p.text),
                ),
              ),
              if (account.active)
                Icon(Icons.check, size: 18, color: p.accent)
              else
                Text(
                  '${account.userId}',
                  style: t.listTime.copyWith(color: p.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    final color = accent ? p.accent : p.text;
    return InkWell(
      onTap: onTap,
      hoverColor: p.windowBgOver,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                icon,
                size: theme.metrics.iconSize,
                color: accent ? p.accent : p.icon,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label, style: t.listPreview.copyWith(color: color)),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
