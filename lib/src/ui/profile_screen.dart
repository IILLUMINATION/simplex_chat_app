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
              'No profile yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a profile to start messaging',
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
    final activeUserId = _userData?['userId'] as int?;

    return RefreshIndicator(
      onRefresh: _loadUserData,
      child: ListView(
        children: [
          // Profile header
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

          // Details
          if (userId != null)
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('User ID'),
              subtitle: Text('$userId'),
            ),

          const Divider(),

          // Actions
          ListTile(
            leading: const Icon(Icons.person_add),
            title: const Text('Create new profile'),
            subtitle: const Text('If you want a new profile, delete current first'),
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
            title: const Text('Refresh'),
            onTap: _loadUserData,
          ),
          if (userId != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete profile'),
              subtitle: const Text('Removes active user from the core'),
              enabled: !_busy,
              onTap: _busy ? null : () => _confirmDelete(userId),
            ),
          if (_users.isNotEmpty) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Profiles',
                style: TextStyle(fontWeight: FontWeight.bold),
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
                subtitle: Text('User ID: ${id ?? '-'}'),
                trailing: isActive
                    ? const Text('Active')
                    : TextButton(
                        onPressed: (_busy || id == null)
                            ? null
                            : () => _switchUser(id),
                        child: const Text('Activate'),
                      ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(int userId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete profile?'),
        content: const Text(
          'This will delete the active user profile in the TangleX core. '
          'You can create a new one after.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Profile deleted' : 'Failed to delete profile',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
    setState(() => _busy = false);
  }

  Future<void> _switchUser(int userId) async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Active profile updated' : 'Failed to switch profile'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
    setState(() => _busy = false);
  }
}
