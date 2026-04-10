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
      appBar: AppBar(
        title: Text([
          loc.translate('chats'),
          loc.translate('profile'),
        ][_currentIndex]),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () => _openDebug(context),
            tooltip: loc.translate('debug_console'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _openSettings(context),
            tooltip: loc.translate('settings'),
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
}
