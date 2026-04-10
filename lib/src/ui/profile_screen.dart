import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart';
import '../localization/app_localizations.dart';
import '../providers/persistent_store.dart';
import 'create_profile_screen.dart';

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
    setState(() {
      _userData = user;
      _users = users;
    });
  }

  void _showSnackBar(String message, bool success) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? cs.onInverseSurface : cs.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final profileAsync = ref.watch(persistedProfileProvider);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _buildNoProfile(loc),
      data: (profile) {
        if (profile == null && _userData == null) {
          return _buildNoProfile(loc);
        }

        return _buildProfileDisplay(profile, loc);
      },
    );
  }

  Widget _buildNoProfile(AppLocalizations loc) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 80,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              loc.translate('no_profile_yet'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              loc.translate('create_profile_description'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 24),
            Consumer(
              builder: (context, ref, _) {
                final service = ref.watch(tanglexServiceProvider);
                return FilledButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreateProfileScreen(service: service),
                      ),
                    );
                    await _loadUserData();
                    if (mounted) {
                      ref.invalidate(persistedProfileProvider);
                    }
                  },
                  icon: const Icon(Icons.person_add),
                  label: Text(loc.translate('create_profile')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileDisplay(ProfileData? profile, AppLocalizations loc) {
    final displayName = profile?.displayName ??
        _userData?['localDisplayName'] as String? ??
        'Unknown';
    final fullName = profile?.fullName ??
        _userData?['profile']?['fullName'] as String? ??
        '';
    final shortDescr = profile?.shortDescr ??
        _userData?['profile']?['shortDescr'] as String? ??
        '';
    final userId = profile?.userId ?? _userData?['userId'] as int?;

    return RefreshIndicator(
      onRefresh: _loadUserData,
      child: ListView(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person,
                    size: 48,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (fullName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    fullName,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
                if (shortDescr.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(shortDescr),
                  ),
                ],
              ],
            ),
          ),
          const Divider(),

          if (userId != null)
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: Text(loc.translate('user_id')),
              subtitle: Text('$userId'),
            ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.person_add),
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
              if (mounted) {
                ref.invalidate(persistedProfileProvider);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(loc.translate('refresh')),
            onTap: _loadUserData,
          ),
          if (userId != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(loc.translate('delete_profile')),
              subtitle: Text(loc.translate('delete_profile_hint')),
              enabled: !_busy,
              onTap: _busy ? null : () => _confirmDelete(userId),
            ),
          if (_users.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                loc.translate('profiles'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            ..._users.map((entry) {
              final user = entry['user'] as Map<String, dynamic>? ?? {};
              final name = user['localDisplayName'] as String? ??
                  user['profile']?['displayName'] as String? ??
                  'Unknown';
              final id = user['userId'] as int?;
              final isActive = user['activeUser'] == true;
              return ListTile(
                leading: Icon(isActive ? Icons.check_circle : Icons.circle_outlined),
                title: Text(name),
                subtitle: Text(loc.translate('user_id_value').replaceAll('%s', id?.toString() ?? '-')),
                trailing: isActive
                    ? Text(loc.translate('active'))
                    : TextButton(
                        onPressed: (_busy || id == null)
                            ? null
                            : () => _switchUser(id),
                        child: Text(loc.translate('activate')),
                      ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(int userId) async {
    final loc = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.translate('delete_profile_confirm')),
        content: Text(loc.translate('delete_profile_warning')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc.translate('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc.translate('delete')),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    final service = ref.read(tanglexServiceProvider);
    final success = await service.deleteUser(userId);
    if (success) {
      await clearProfileData();
      _userData = null;
      if (mounted) {
        ref.invalidate(persistedProfileProvider);
      }
      await _loadUserData();
    }
    if (mounted) {
      _showSnackBar(
        success ? loc.translate('profile_deleted') : loc.translate('failed_delete_profile'),
        success,
      );
    }
    setState(() => _busy = false);
  }

  Future<void> _switchUser(int userId) async {
    final loc = AppLocalizations.of(context);
    setState(() => _busy = true);
    final service = ref.read(tanglexServiceProvider);
    final success = await service.setActiveUser(userId);
    if (success) {
      await _loadUserData();
      if (mounted) {
        ref.invalidate(persistedProfileProvider);
      }
    }
    if (mounted) {
      _showSnackBar(
        success ? loc.translate('profile_updated') : loc.translate('failed_switch_profile'),
        success,
      );
    }
    setState(() => _busy = false);
  }
}
