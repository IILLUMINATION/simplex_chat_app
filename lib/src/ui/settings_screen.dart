// Settings screen. Currently exposes only the locale selector.
// Theme is fixed (dark-only) per DESIGN.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_localizations.dart';
import '../providers/locale_provider.dart';
import 'design/design.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);
    final localeConfig = ref.watch(localeNotifierProvider);
    final current = AppLocale.fromCode(localeConfig.locale);

    return Scaffold(
      appBar: AppBar(title: Text(loc.translate('settings'))),
      body: ListView(
        children: [
          const _SectionHeader(),
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: Text(loc.translate('language')),
          ),
          ...AppLocale.values.map((appLocale) {
            return ListTile(
              leading: Radio<AppLocale>(
                // ignore: deprecated_member_use
                value: appLocale,
                // ignore: deprecated_member_use
                groupValue: current,
                // ignore: deprecated_member_use
                onChanged: (value) {
                  if (value != null) {
                    ref.read(localeNotifierProvider.notifier).setLocale(value);
                  }
                },
              ),
              title: Text(loc.translate(appLocale.name)),
              onTap: () {
                ref
                    .read(localeNotifierProvider.notifier)
                    .setLocale(appLocale);
              },
            );
          }),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s4,
        AppSpacing.s4,
        AppSpacing.s1,
      ),
      child: Text(
        AppLocalizations.of(context).translate('language').toUpperCase(),
        style: AppText.meta.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
