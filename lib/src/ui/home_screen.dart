import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart';
import '../localization/app_localizations.dart';
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
  int _currentIndex = 0;
  bool _coreInitializing = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _screens = [
    ChatsScreen(),
    ProfileScreen(),
  ];

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

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(context, loc),
      appBar: AppBar(
        title: const Text('TangleX Chat'),
        leading: _currentIndex == 0
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: implement search
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: () => ref.read(fabActionProvider).trigger(),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: loc.translate('chats'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: loc.translate('profile'),
          ),
        ],
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

  Widget _buildDrawer(BuildContext context, AppLocalizations loc) {
    return Drawer(
      backgroundColor: const Color(0xFF000000),
      child: SafeArea(
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF333333), width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Color(0xFF2A2A2A),
                    child: Icon(Icons.person, size: 30, color: Color(0xFF808080)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loc.translate('profile'),
                    style: const TextStyle(
                      color: Color(0xFFE8E8E8),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
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
            ListTile(
              leading: const Icon(Icons.bug_report, color: Color(0xFF808080)),
              title: Text(
                loc.translate('debug_console'),
                style: const TextStyle(color: Color(0xFF808080)),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DebugScreenWrapper()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
