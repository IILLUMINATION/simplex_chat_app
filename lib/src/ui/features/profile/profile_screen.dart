// TangleX — read-only profile screen.
//
// Displays the active user's displayName/fullName/shortDescr fetched from the
// core. Also exposes a language switcher (the only persistent preference the
// app surfaces in this MVP). Editing the profile and adding/switching users
// is out of scope (HANDOFF.md § 16 MVP).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart';
import '../../../localization/app_localizations.dart';
import '../../../providers/locale_provider.dart';
import '../../shared/avatar.dart';
import '../../shared/empty_state.dart';

final _activeUserProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final service = ref.watch(tanglexServiceProvider);
  if (!service.isInitialized) return null;
  return service.getUser();
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final user = ref.watch(_activeUserProvider);
    final localeData = ref.watch(localeNotifierProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_activeUserProvider),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar.medium(
            title: Text(t.translate('profile')),
            pinned: true,
          ),
          user.when(
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: TxEmptyState(
                icon: Icons.error_outline_rounded,
                title: t.translate('initialization_error'),
                subtitle: err.toString(),
              ),
            ),
            data: (data) {
              final profile = data?['profile'] as Map<String, dynamic>?;
              final displayName =
                  (profile?['displayName'] as String?)?.trim() ?? '';
              final fullName = (profile?['fullName'] as String?)?.trim() ?? '';
              final descr =
                  (profile?['shortDescr'] as String?)?.trim() ?? '';

              if (profile == null || displayName.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: TxEmptyState(
                    icon: Icons.person_outline_rounded,
                    title: t.translate('profile_no_profile'),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildListDelegate.fixed([
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      children: [
                        TxAvatar(name: displayName, size: 96),
                        const SizedBox(height: 16),
                        Text(
                          displayName,
                          style: tt.headlineSmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (fullName.isNotEmpty && fullName != displayName) ...[
                          const SizedBox(height: 4),
                          Text(
                            fullName,
                            style: tt.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (descr.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            descr,
                            textAlign: TextAlign.center,
                            style: tt.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Divider(color: cs.outlineVariant, height: 1),
                  _LanguageTile(currentCode: localeData.locale, ref: ref),
                  Divider(color: cs.outlineVariant, height: 1),
                ]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({required this.currentCode, required this.ref});

  final String currentCode;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListTile(
      leading: Icon(Icons.translate_rounded, color: cs.onSurfaceVariant),
      title: Text(t.translate('language_label')),
      subtitle: Text(
        currentCode == 'ru' ? t.translate('russian') : t.translate('english'),
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'en', label: Text('EN')),
          ButtonSegment(value: 'ru', label: Text('RU')),
        ],
        selected: {currentCode},
        showSelectedIcon: false,
        onSelectionChanged: (set) {
          if (set.isEmpty) return;
          final code = set.first;
          final locale = AppLocale.fromCode(code);
          ref.read(localeNotifierProvider.notifier).setLocale(locale);
        },
      ),
    );
  }
}
