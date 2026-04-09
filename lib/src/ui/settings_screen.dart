import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_localizations.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);
    final themeConfig = ref.watch(themeNotifierProvider);
    final localeConfig = ref.watch(localeNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.translate('settings')),
      ),
      body: ListView(
        children: [
          // ===== Theme Mode =====
          ListTile(
            leading: const Icon(Icons.brightness_auto),
            title: Text(loc.translate('theme_mode')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<AppThemeMode>(
              segments: [
                ButtonSegment(
                  value: AppThemeMode.light,
                  label: Text(loc.translate('light')),
                  icon: const Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: AppThemeMode.system,
                  label: Text(loc.translate('system')),
                  icon: const Icon(Icons.settings_brightness),
                ),
                ButtonSegment(
                  value: AppThemeMode.dark,
                  label: Text(loc.translate('dark')),
                  icon: const Icon(Icons.dark_mode),
                ),
              ],
              selected: {AppThemeMode.fromName(themeConfig.mode)},
              onSelectionChanged: (modes) {
                ref.read(themeNotifierProvider.notifier).setMode(modes.first);
              },
            ),
          ),
          const Divider(),

          // ===== Theme Style =====
          ListTile(
            leading: const Icon(Icons.palette),
            title: Text(loc.translate('theme_style')),
          ),
          ...AppTheme.values.map((theme) {
            return ListTile(
              leading: Radio<AppTheme>(
                // ignore: deprecated_member_use
                value: theme,
                // ignore: deprecated_member_use
                groupValue: AppTheme.fromName(themeConfig.theme),
                // ignore: deprecated_member_use
                onChanged: (value) {
                  ref.read(themeNotifierProvider.notifier).setTheme(value!);
                },
              ),
              title: Text(loc.translate(theme.name)),
              onTap: () {
                ref.read(themeNotifierProvider.notifier).setTheme(theme);
              },
            );
          }),
          const Divider(),

          // ===== Language =====
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(loc.translate('language')),
          ),
          ...AppLocale.values.map((appLocale) {
            final current = AppLocale.fromCode(localeConfig.locale);
            return ListTile(
              leading: Radio<AppLocale>(
                // ignore: deprecated_member_use
                value: appLocale,
                // ignore: deprecated_member_use
                groupValue: current,
                // ignore: deprecated_member_use
                onChanged: (value) {
                  ref.read(localeNotifierProvider.notifier).setLocale(value!);
                  _restartForLocale(ref);
                },
              ),
              title: Text(loc.translate(appLocale.name)),
              onTap: () {
                ref.read(localeNotifierProvider.notifier).setLocale(appLocale);
                _restartForLocale(ref);
              },
            );
          }),
        ],
      ),
    );
  }

  void _restartForLocale(WidgetRef ref) {
    // Just save — user should restart app manually or we force rebuild
    // For now, a simpleSnackBar to inform
  }
}
