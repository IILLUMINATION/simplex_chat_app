// Profile screen: shows the active user profile, list of other profiles
// (one-tap switch), and exposes "create new" / "delete" actions.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart';
import '../localization/app_localizations.dart';
import '../providers/persistent_store.dart';
import 'create_profile_screen.dart';
import 'design/design.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _users = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final service = ref.read(tanglexServiceProvider);
    if (!service.isInitialized) return;
    final user = await service.getUser();
    final users = await service.getUsers();
    if (!mounted) return;
    setState(() {
      _userData = user;
      _users = users;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final profileAsync = ref.watch(persistedProfileProvider);

    return Scaffold(
      appBar: AppBar(title: Text(loc.translate('profile_default_name'))),
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
        error: (_, _) => _buildNoProfile(loc),
        data: (profile) {
          if (profile == null && _userData == null) {
            return _buildNoProfile(loc);
          }
          return _buildProfileDisplay(profile, loc);
        },
      ),
    );
  }

  Widget _buildNoProfile(AppLocalizations loc) {
    final service = ref.watch(tanglexServiceProvider);
    return AppEmptyState(
      icon: Icons.person_outline_rounded,
      title: loc.translate('no_profile_yet'),
      hint: loc.translate('create_profile_description'),
      action: AppPrimaryButton(
        label: loc.translate('create_profile'),
        icon: Icons.person_add_rounded,
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateProfileScreen(service: service),
            ),
          );
          await _loadUserData();
          if (mounted) ref.invalidate(persistedProfileProvider);
        },
      ),
    );
  }

  Widget _buildProfileDisplay(ProfileData? profile, AppLocalizations loc) {
    final displayName = profile?.displayName ??
        _userData?['localDisplayName'] as String? ??
        loc.translate('profile_default_name');
    final fullName = profile?.fullName ??
        _userData?['profile']?['fullName'] as String? ??
        '';
    final shortDescr = profile?.shortDescr ??
        _userData?['profile']?['shortDescr'] as String? ??
        '';
    final userId = profile?.userId ?? _userData?['userId'] as int?;

    return RefreshIndicator(
      onRefresh: _loadUserData,
      color: AppColors.accent,
      child: ListView(
        children: [
          // ===== Header =====
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s6,
            ),
            child: Column(
              children: [
                AppAvatar(name: displayName, size: AppAvatarSize.xlarge),
                const SizedBox(height: AppSpacing.s4),
                Text(displayName, style: AppText.display),
                if (fullName.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s1),
                  Text(fullName, style: AppText.caption),
                ],
                if (shortDescr.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s3,
                      vertical: AppSpacing.s2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: AppRadius.brm,
                    ),
                    child: Text(shortDescr, style: AppText.body),
                  ),
                ],
              ],
            ),
          ),
          const AppDivider(),

          if (userId != null)
            ListTile(
              leading: const Icon(Icons.fingerprint_rounded),
              title: Text(loc.translate('user_id')),
              subtitle: Text('$userId', style: AppText.caption),
            ),

          const AppDivider(),

          ListTile(
            leading: const Icon(Icons.person_add_rounded),
            title: Text(loc.translate('create_new_profile')),
            subtitle: Text(loc.translate('create_new_profile_hint')),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateProfileScreen(
                    service: ref.read(tanglexServiceProvider),
                  ),
                ),
              );
              await _loadUserData();
              if (mounted) ref.invalidate(persistedProfileProvider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh_rounded),
            title: Text(loc.translate('refresh')),
            onTap: _loadUserData,
          ),
          if (userId != null)
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: Text(
                loc.translate('delete_profile'),
                style: AppText.body.copyWith(color: AppColors.error),
              ),
              subtitle: Text(loc.translate('delete_profile_hint')),
              enabled: !_busy,
              onTap: _busy ? null : () => _confirmDelete(userId),
            ),
          if (_users.isNotEmpty) ...[
            const AppDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s4,
                AppSpacing.s4,
                AppSpacing.s2,
              ),
              child: Text(
                loc.translate('profiles').toUpperCase(),
                style: AppText.meta.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ..._users.map((entry) {
              final user = entry['user'] as Map<String, dynamic>? ?? {};
              final name = user['localDisplayName'] as String? ??
                  user['profile']?['displayName'] as String? ??
                  loc.translate('profile_default_name');
              final id = user['userId'] as int?;
              final isActive = user['activeUser'] == true;
              return ListTile(
                leading: AppAvatar(
                  name: name,
                  size: AppAvatarSize.medium,
                ),
                title: Text(name, style: AppText.bodyEmph),
                subtitle: Text(
                  loc
                      .translate('user_id_value')
                      .replaceAll('%s', id?.toString() ?? '-'),
                  style: AppText.caption,
                ),
                trailing: isActive
                    ? Text(
                        loc.translate('active'),
                        style:
                            AppText.captionEmph.copyWith(color: AppColors.accent),
                      )
                    : TextButton(
                        onPressed: (_busy || id == null)
                            ? null
                            : () => _switchUser(id),
                        child: Text(loc.translate('activate')),
                      ),
              );
            }),
          ],
          const SizedBox(height: AppSpacing.s6),
        ],
      ),
    );
  }

  int? _firstOtherUserId(
      List<Map<String, dynamic>> userInfos, int skipUserId) {
    for (final entry in userInfos) {
      final u = entry['user'] as Map<String, dynamic>?;
      final id = u?['userId'] as int?;
      if (id != null && id != skipUserId) return id;
    }
    return null;
  }

  Future<void> _confirmDelete(int userId) async {
    final loc = AppLocalizations.of(context);
    final ok = await showAppConfirmDialog(
      context: context,
      title: loc.translate('delete_profile_confirm'),
      message: loc.translate('delete_profile_warning'),
      confirmLabel: loc.translate('delete'),
      cancelLabel: loc.translate('cancel'),
      destructive: true,
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final service = ref.read(tanglexServiceProvider);
    var success = await service.deleteUser(userId);
    if (!success && mounted) {
      final current = await service.getUser();
      final activeId = current?['userId'] as int?;
      final users = await service.getUsers();
      if (kDebugMode) {
        debugPrint(
          '[Profile] deleteUser($userId) failed; activeId=$activeId '
          'usersCount=${users.length}',
        );
      }
      if (activeId == userId && users.length > 1) {
        final other = _firstOtherUserId(users, userId);
        if (other != null) {
          final switched = await service.setActiveUser(other);
          if (switched) {
            success = await service.deleteUser(userId);
          }
        }
      }
    }
    if (success && mounted) {
      await clearProfileData();
      _userData = null;
      _users = [];
      await _loadUserData();
    }
    if (!mounted) return;
    showAppSnack(
      context,
      message: success
          ? loc.translate('profile_deleted')
          : loc.translate('failed_delete_profile'),
      kind: success ? AppSnackKind.success : AppSnackKind.error,
    );
    setState(() => _busy = false);
  }

  Future<void> _switchUser(int userId) async {
    final loc = AppLocalizations.of(context);
    setState(() => _busy = true);
    final service = ref.read(tanglexServiceProvider);
    final success = await service.setActiveUser(userId);
    if (success && mounted) {
      final newUser = await service.getUser();
      if (mounted && newUser != null) {
        _userData = newUser;
        final displayName = newUser['localDisplayName'] as String? ?? '';
        final fullName = newUser['profile']?['fullName'] as String? ?? '';
        final shortDescr =
            newUser['profile']?['shortDescr'] as String? ?? '';
        await saveProfileData(ProfileData(
          displayName: displayName,
          fullName: fullName,
          shortDescr: shortDescr,
          userId: newUser['userId'] as int?,
          agentUserId: newUser['agentUserId'] as String?,
          userContactId: newUser['userContactId'] as int?,
          localDisplayName: newUser['localDisplayName'] as String?,
        ));
        ref.invalidate(persistedProfileProvider);
      }
      await _loadUserData();
    }
    if (!mounted) return;
    showAppSnack(
      context,
      message: success
          ? loc.translate('profile_updated')
          : loc.translate('failed_switch_profile'),
      kind: success ? AppSnackKind.success : AppSnackKind.error,
    );
    setState(() => _busy = false);
  }
}
