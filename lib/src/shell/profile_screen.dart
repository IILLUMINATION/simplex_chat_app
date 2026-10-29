import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/account_models.dart';
import '../data/account_providers.dart';
import '../data/profile_image.dart';
import '../design/app_theme.dart';
import 'widgets/peer_avatar.dart';

/// Telegram-style own profile: avatar, name, bio, SimpleX address and edit.
class OwnProfileScreen extends ConsumerStatefulWidget {
  const OwnProfileScreen({super.key});

  @override
  ConsumerState<OwnProfileScreen> createState() => _OwnProfileScreenState();
}

class _OwnProfileScreenState extends ConsumerState<OwnProfileScreen> {
  String? _address;
  bool _loadingAddress = false;
  String? _addressError;

  Future<void> _copyAddress(AccountProfile account) async {
    setState(() {
      _loadingAddress = true;
      _addressError = null;
    });
    var link = _address;
    link ??= await ref.read(accountsProvider.notifier).getAddress();
    if (!mounted) return;
    if (link == null) {
      setState(() {
        _loadingAddress = false;
        _addressError = 'Could not create an address';
      });
      return;
    }
    setState(() {
      _address = link;
      _loadingAddress = false;
    });
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    _toast('SimpleX address copied');
  }

  Future<void> _edit(AccountProfile account) async {
    final draft = await showProfileEditDialog(
      context,
      title: 'Edit profile',
      submitLabel: 'Save',
      initial: ProfileDraft(
        displayName: account.displayName,
        fullName: account.fullName,
        shortDescr: account.shortDescr,
      ),
    );
    if (draft == null || !mounted) return;
    final ok = await ref
        .read(accountsProvider.notifier)
        .updateProfile(
          account.userId,
          displayName: draft.displayName,
          fullName: draft.fullName,
          shortDescr: draft.shortDescr,
          image: account.image,
        );
    if (!mounted) return;
    _toast(ok ? 'Profile updated' : 'Could not update the profile');
  }

  Future<Uint8List?> _pickProfileImage() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = result?.files.single.path;
      return path == null ? null : File(path).readAsBytes();
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    return picked?.readAsBytes();
  }

  Future<void> _savePhoto(AccountProfile account, String? image) async {
    final ok = await ref
        .read(accountsProvider.notifier)
        .updateProfile(
          account.userId,
          displayName: account.displayName,
          fullName: account.fullName,
          shortDescr: account.shortDescr,
          image: image,
        );
    if (!mounted) return;
    _toast(ok ? 'Profile photo updated' : 'Could not update the photo');
  }

  Future<void> _changePhoto(AccountProfile account) async {
    final bytes = await _pickProfileImage();
    if (bytes == null || !mounted) return;
    final image = profileImageDataUri(bytes);
    if (image == null) {
      _toast('Could not read that image');
      return;
    }
    await _savePhoto(account, image);
  }

  /// Telegram Desktop opens a small menu on the profile photo: set a new one
  /// or remove the current one. Same two actions here.
  Future<void> _showAvatarMenu(
    AccountProfile account,
    BuildContext avatarContext,
  ) async {
    final box = avatarContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(avatarContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
    final hasPhoto = account.image != null && account.image!.isNotEmpty;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'set', child: Text('Set new photo')),
        if (hasPhoto)
          const PopupMenuItem(value: 'delete', child: Text('Delete photo')),
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'set') {
      await _changePhoto(account);
    } else if (action == 'delete') {
      await _savePhoto(account, null);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final m = theme.metrics;
    final t = theme.typography;
    final accounts = ref.watch(accountsProvider);
    final state = accounts.valueOrNull;
    final account = state?.active;

    return Scaffold(
      backgroundColor: p.windowBg,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: m.topBarHeight,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  _IconAction(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'My Profile',
                      style: t.chatTitle.copyWith(color: p.text),
                    ),
                  ),
                  if (account != null)
                    _IconAction(
                      icon: Icons.edit_outlined,
                      onTap: () => _edit(account),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Container(height: 1, color: p.divider),
            Expanded(
              child: switch (accounts) {
                AsyncError(:final error) when state == null => _Centered(
                  icon: Icons.error_outline,
                  title: 'Profile is not available',
                  detail: '$error',
                  onRetry: () => ref.invalidate(accountsProvider),
                ),
                AsyncLoading() when state == null => const _Centered(
                  icon: Icons.hourglass_empty,
                  title: 'Loading profile…',
                ),
                _ when account == null => const _Centered(
                  icon: Icons.person_off_outlined,
                  title: 'No profile yet',
                  detail: 'Create a profile from the side menu.',
                ),
                _ => _ProfileBody(
                  account: account,
                  address: _address,
                  loadingAddress: _loadingAddress,
                  addressError: _addressError,
                  onCopyAddress: () => _copyAddress(account),
                  onEdit: () => _edit(account),
                  onPhotoTap: (avatarContext) => _showAvatarMenu(
                    account,
                    avatarContext,
                  ),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({
    required this.account,
    required this.address,
    required this.loadingAddress,
    required this.addressError,
    required this.onCopyAddress,
    required this.onEdit,
    required this.onPhotoTap,
  });

  final AccountProfile account;
  final String? address;
  final bool loadingAddress;
  final String? addressError;
  final VoidCallback onCopyAddress;
  final VoidCallback onEdit;
  final ValueChanged<BuildContext> onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
      children: [
        Center(
          child: Builder(
            builder: (avatarContext) => GestureDetector(
              key: const ValueKey('profile-avatar'),
              onTap: () => onPhotoTap(avatarContext),
              child: PeerAvatar(
                seed: 'user-${account.userId}',
                title: account.displayName,
                size: 112,
                fontSize: 40,
                imageBytes: profileImageBytes(account.image),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            account.displayName,
            textAlign: TextAlign.center,
            style: t.chatTitle.copyWith(color: p.text, fontSize: 20),
          ),
        ),
        if (account.localDisplayName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Center(
            child: Text(
              '@${account.localDisplayName}',
              style: t.listTime.copyWith(color: p.link),
            ),
          ),
        ],
        if (account.fullName.isNotEmpty) ...[
          const SizedBox(height: 6),
          Center(
            child: Text(
              account.fullName,
              textAlign: TextAlign.center,
              style: t.listPreview.copyWith(color: p.textSecondary),
            ),
          ),
        ],
        if (account.shortDescr.isNotEmpty) ...[
          const SizedBox(height: 10),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                account.shortDescr,
                textAlign: TextAlign.center,
                style: t.listPreview.copyWith(color: p.text),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ActionButton(
              label: 'Copy link',
              icon: Icons.link,
              filled: true,
              busy: loadingAddress,
              onTap: onCopyAddress,
            ),
            const SizedBox(width: 10),
            _ActionButton(
              label: 'Edit profile',
              icon: Icons.edit_outlined,
              filled: false,
              onTap: onEdit,
            ),
          ],
        ),
        if (addressError != null) ...[
          const SizedBox(height: 10),
          Center(
            child: Text(
              addressError!,
              style: t.listTime.copyWith(color: p.error),
            ),
          ),
        ],
        const SizedBox(height: 28),
        Text(
          'SIMPLEX ADDRESS',
          style: t.sectionHeader.copyWith(
            color: p.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        _InfoCard(
          icon: Icons.alternate_email,
          title: address ?? 'Not created yet',
          subtitle: address == null
              ? 'Share a link so people can connect with this profile'
              : 'Tap Copy link to share this address',
          trailing: IconButton(
            onPressed: onCopyAddress,
            icon: Icon(
              address == null ? Icons.add_link : Icons.copy,
              size: theme.metrics.iconSize * 0.8,
              color: p.icon,
            ),
            tooltip: address == null ? 'Create address' : 'Copy address',
          ),
        ),
        const SizedBox(height: 14),
        _InfoCard(
          icon: Icons.badge_outlined,
          title: 'Profile ${account.userId}',
          subtitle: 'Local SimpleX profile on this device',
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: p.windowBgOver,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: theme.metrics.iconSize, color: p.icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.listPreview.copyWith(color: p.text),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: t.listTime.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    final fg = filled ? p.onAccent : p.accent;
    return Material(
      color: filled ? p.accent : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: filled ? BorderSide.none : BorderSide(color: p.accent),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              else
                Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(label, style: t.button.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

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

class _Centered extends StatelessWidget {
  const _Centered({
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
    return Center(
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
    );
  }
}

/// Values collected by the create/edit profile dialog.
class ProfileDraft {
  const ProfileDraft({
    required this.displayName,
    this.fullName = '',
    this.shortDescr = '',
  });

  final String displayName;
  final String fullName;
  final String shortDescr;
}

Future<ProfileDraft?> showProfileEditDialog(
  BuildContext context, {
  required String title,
  required String submitLabel,
  ProfileDraft? initial,
  String? description,
}) {
  return showDialog<ProfileDraft>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (_) => _ProfileEditDialog(
      title: title,
      submitLabel: submitLabel,
      initial: initial,
      description: description,
    ),
  );
}

class _ProfileEditDialog extends StatefulWidget {
  const _ProfileEditDialog({
    required this.title,
    required this.submitLabel,
    required this.initial,
    this.description,
  });

  final String title;
  final String submitLabel;
  final ProfileDraft? initial;
  final String? description;

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  late final _name = TextEditingController(
    text: widget.initial?.displayName ?? '',
  );
  late final _fullName = TextEditingController(
    text: widget.initial?.fullName ?? '',
  );
  late final _bio = TextEditingController(text: widget.initial?.shortDescr ?? '');
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _valid = _name.text.trim().isNotEmpty;
    _name.addListener(() {
      final valid = _name.text.trim().isNotEmpty;
      if (valid != _valid) setState(() => _valid = valid);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _fullName.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(
      ProfileDraft(
        displayName: _name.text.trim(),
        fullName: _fullName.text.trim(),
        shortDescr: _bio.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;

    return Dialog(
      backgroundColor: p.windowBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: t.chatTitle.copyWith(color: p.text)),
              if (widget.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.description!,
                  style: t.listPreview.copyWith(color: p.textSecondary),
                ),
              ],
              const SizedBox(height: 16),
              _Field(controller: _name, label: 'Name', autofocus: true),
              const SizedBox(height: 10),
              _Field(controller: _fullName, label: 'Last name'),
              const SizedBox(height: 10),
              _Field(controller: _bio, label: 'Bio', maxLines: 3),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: TextButton.styleFrom(foregroundColor: p.accent),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _valid ? _submit : null,
                    style: TextButton.styleFrom(foregroundColor: p.accent),
                    child: Text(widget.submitLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      style: theme.typography.input.copyWith(color: p.text),
      cursorColor: p.accent,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: theme.typography.listPreview.copyWith(
          color: p.textSecondary,
        ),
        filled: true,
        fillColor: p.windowBgOver,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.accent),
        ),
      ),
    );
  }
}
