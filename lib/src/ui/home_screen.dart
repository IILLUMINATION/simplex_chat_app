import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart';
import '../localization/app_localizations.dart';
import '../providers/persistent_store.dart';
import 'chats_screen.dart';
import 'debug_screen.dart';
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
    } catch (e) {
      // Silently fail — user can see logs in debug screen
    } finally {
      _coreInitializing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final profileAsync = ref.watch(persistedProfileProvider);

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(context, loc, profileAsync),
      appBar: AppBar(
        title: const Text('TangleX Chat'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: implement search
            },
          ),
        ],
      ),
      body: const ChatsScreen(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.read(fabActionProvider).trigger(),
        backgroundColor: const Color(0xFF5A9CF5),
        elevation: 4,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  void _openDebug(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DebugScreenWrapper()),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    AppLocalizations loc,
    AsyncValue<ProfileData?> profileAsync,
  ) {
    return Drawer(
      backgroundColor: const Color(0xFF000000),
      child: SafeArea(
        child: Column(
          children: [
            // Profile header
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _openProfile(context);
              },
              child: profileAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF5A9CF5),
                      ),
                    ),
                  ),
                ),
                error: (_, __) =>
                    _DrawerProfilePlaceholder(name: 'Error loading profile'),
                data: (profile) {
                  final dn = profile?.displayName ?? '';
                  final ln = profile?.localDisplayName ?? '';
                  final name = dn.isNotEmpty
                      ? dn
                      : ln.isNotEmpty
                      ? ln
                      : 'Profile';
                  return _DrawerProfilePlaceholder(name: name);
                },
              ),
            ),
            const Divider(color: Color(0xFF333333), height: 1),
            // Search
            ListTile(
              leading: const Icon(Icons.search, color: Color(0xFF808080)),
              title: Text(
                loc.translate('search'),
                style: const TextStyle(color: Color(0xFFE8E8E8)),
              ),
              onTap: () {
                Navigator.pop(context);
                // TODO: open search
              },
            ),
            // Settings
            ListTile(
              leading: const Icon(Icons.settings, color: Color(0xFF808080)),
              title: Text(
                loc.translate('settings'),
                style: const TextStyle(color: Color(0xFFE8E8E8)),
              ),
              onTap: () {
                Navigator.pop(context);
                _openSettings(context);
              },
            ),
            const Spacer(),
            const Divider(color: Color(0xFF333333), height: 1),
            // Debug
            ListTile(
              leading: const Icon(Icons.bug_report, color: Color(0xFF808080)),
              title: Text(
                loc.translate('debug_console'),
                style: const TextStyle(color: Color(0xFF808080)),
              ),
              onTap: () {
                Navigator.pop(context);
                _openDebug(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerProfilePlaceholder extends StatelessWidget {
  final String name;

  const _DrawerProfilePlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xFF2A2A2A),
            child: Icon(Icons.person, size: 28, color: Color(0xFF808080)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE8E8E8),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Tap to view profile',
                  style: TextStyle(color: Color(0xFF808080), fontSize: 13),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: Color(0xFF555555),
          ),
        ],
      ),
    );
  }
}
