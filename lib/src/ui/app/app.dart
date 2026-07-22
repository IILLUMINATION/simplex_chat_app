// TangleX — app shell.
//
// MaterialApp wired with the Material 3 dark theme, localization, and a
// NavigationBar shell that hosts the top-level tabs (Chats, Profile). The
// actual screens come from `features/*`. This file must stay short (HANDOFF
// § 10: ≤ 300 lines / ≤ 200 for screen widgets).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../localization/app_localizations.dart';
import '../../providers/locale_provider.dart';
import '../features/chats/chats_screen.dart';
import '../features/profile/profile_screen.dart';
import '../shared/core_status.dart';
import 'theme.dart';

class TangleXApp extends ConsumerWidget {
  const TangleXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeConfig = ref.watch(localeNotifierProvider);
    final locale = AppLocale.fromCode(localeConfig.locale);

    return MaterialApp(
      title: 'TangleX',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: buildDarkTheme(),
      theme: buildLightTheme(),
      locale: locale.flutterLocale,
      supportedLocales: const [Locale('en'), Locale('ru')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const CoreBootGate(child: _HomeShell()),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final pages = <Widget>[
      const ChatsScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: const Icon(Icons.chat_bubble_rounded),
            label: t.translate('chats'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded),
            label: t.translate('profile'),
          ),
        ],
      ),
    );
  }
}
