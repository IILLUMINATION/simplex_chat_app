import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/localization/app_localizations.dart';
import 'src/providers/locale_provider.dart';
import 'src/providers/theme_provider.dart';
import 'src/service/tanglex_service.dart';
import 'src/ui/home_screen.dart';

// Global provider so all screens share the same TanglexService
final tanglexServiceProvider = Provider<TanglexService>((ref) {
  final service = TanglexService();
  ref.onDispose(() => service.dispose());
  return service;
});

void main() {
  runApp(const ProviderScope(child: TangleXApp()));
}

class TangleXApp extends ConsumerWidget {
  const TangleXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeConfig = ref.watch(themeNotifierProvider);
    final localeConfig = ref.watch(localeNotifierProvider);
    final notifier = ref.watch(themeNotifierProvider.notifier);
    final locale = AppLocale.fromCode(localeConfig.locale);

    return MaterialApp(
      title: 'TangleX Chat',
      debugShowCheckedModeBanner: false,
      themeMode: AppThemeMode.fromName(themeConfig.mode).flutterMode,
      theme: notifier.lightTheme,
      darkTheme: notifier.darkTheme,
      locale: locale.flutterLocale,
      supportedLocales: const [
        Locale('en'),
        Locale('ru'),
      ],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeScreen(),
    );
  }
}
