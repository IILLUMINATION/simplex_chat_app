// Home shell: scaffolds the AppBar, drawer, FAB and hosts the chats list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart';
import '../localization/app_localizations.dart';
import '../providers/persistent_store.dart';
import 'chats_screen.dart';
import 'debug_screen.dart';
import 'design/design.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _coreInitializing = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _autoInitCore();
  }

  Future<void> _autoInitCore() async {
    if (_coreInitializing) return;
    _coreInitializing = true;
    try {
      final service = ref.read(tanglexServiceProvider);
      if (!service.isInitialized) {
        await service.initialize();
      }
    } catch (_) {
      // Silently fail — user can see logs in debug screen.
    } finally {
      _coreInitializing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(persistedProfileProvider);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bg,
      drawer: _Drawer(
        profileAsync: profileAsync,
        onOpenProfile: () => _push(const ProfileScreen()),
        onOpenSettings: () => _push(const SettingsScreen()),
        onOpenDebug: () => _push(const DebugScreenWrapper()),
      ),
      appBar: AppBar(
        title: const Text('TangleX'),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      body: const ChatsScreen(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.read(fabActionProvider).trigger(),
        child: const Icon(Icons.add_rounded, size: AppIconSize.large),
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _Drawer extends StatelessWidget {
  const _Drawer({
    required this.profileAsync,
    required this.onOpenProfile,
    required this.onOpenSettings,
    required this.onOpenDebug,
  });

  final AsyncValue<ProfileData?> profileAsync;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenDebug;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Drawer(
      backgroundColor: AppColors.surface1,
      child: SafeArea(
        child: Column(
          children: [
            _DrawerProfileHeader(
              profileAsync: profileAsync,
              onTap: () {
                Navigator.pop(context);
                onOpenProfile();
              },
            ),
            const AppDivider(),
            ListTile(
              leading: const Icon(Icons.settings_rounded),
              title: Text(loc.translate('settings')),
              onTap: () {
                Navigator.pop(context);
                onOpenSettings();
              },
            ),
            const Spacer(),
            const AppDivider(),
            ListTile(
              leading: const Icon(
                Icons.bug_report_outlined,
                color: AppColors.textSecondary,
              ),
              title: Text(
                loc.translate('debug_console'),
                style: AppText.body.copyWith(color: AppColors.textSecondary),
              ),
              onTap: () {
                Navigator.pop(context);
                onOpenDebug();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerProfileHeader extends StatelessWidget {
  const _DrawerProfileHeader({
    required this.profileAsync,
    required this.onTap,
  });

  final AsyncValue<ProfileData?> profileAsync;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return InkWell(
      onTap: onTap,
      child: profileAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.s5),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
          ),
        ),
        error: (_, _) => _row(loc.translate('profile_default_name'),
            loc.translate('profile_tap_to_view')),
        data: (profile) {
          final dn = profile?.displayName ?? '';
          final ln = profile?.localDisplayName ?? '';
          String name;
          if (dn.isNotEmpty) {
            name = dn;
          } else if (ln.isNotEmpty) {
            name = ln;
          } else {
            name = loc.translate('profile_default_name');
          }
          return _row(name, loc.translate('profile_tap_to_view'));
        },
      ),
    );
  }

  Widget _row(String name, String hint) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s5),
      child: Row(
        children: [
          AppAvatar(name: name, size: AppAvatarSize.medium),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyEmph,
                ),
                const SizedBox(height: 2),
                Text(hint, style: AppText.caption),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}


