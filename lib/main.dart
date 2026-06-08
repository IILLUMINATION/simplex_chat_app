// TangleX — entry point.
//
// This file is intentionally minimal: it boots the core (FFI service,
// localization, Riverpod) and shows a placeholder Scaffold so the build is
// runnable.  All product UI was removed in commit
// "refactor: drop UI layer, replace with minimal bootstrap" — see HANDOFF.md
// at the repo root for the migration plan.
//
// Anything inside [BootstrapScreen] is throwaway. The next person writing the
// UI replaces it entirely.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/localization/app_localizations.dart';
import 'src/providers/locale_provider.dart';
import 'src/service/tanglex_service.dart';

/// Global Riverpod provider for the FFI-backed SimpleX service.
///
/// Disposed automatically with the [ProviderScope] that hosts the app.
final tanglexServiceProvider = Provider<TanglexService>((ref) {
  final service = TanglexService();
  ref.onDispose(service.dispose);
  return service;
});

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: TangleXApp()));
}

class TangleXApp extends ConsumerWidget {
  const TangleXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeConfig = ref.watch(localeNotifierProvider);
    final locale = AppLocale.fromCode(localeConfig.locale);

    // Material 3 dark scheme generated from a seed.  This is intentionally
    // bare-bones — the real design is provided by the user in a separate
    // DESIGN doc (see HANDOFF.md § "Next steps").
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2AABEE),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'TangleX',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surface,
      ),
      locale: locale.flutterLocale,
      supportedLocales: const [Locale('en'), Locale('ru')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const BootstrapScreen(),
    );
  }
}

/// Placeholder home screen.
///
/// Shows the app title and a single chip reflecting the core (FFI service)
/// readiness state. Replace with the real UI when it ships.
class BootstrapScreen extends ConsumerStatefulWidget {
  const BootstrapScreen({super.key});

  @override
  ConsumerState<BootstrapScreen> createState() => _BootstrapScreenState();
}

enum _CoreStatus { initializing, ready, failed }

class _BootstrapScreenState extends ConsumerState<BootstrapScreen> {
  _CoreStatus _status = _CoreStatus.initializing;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootCore();
  }

  Future<void> _bootCore() async {
    final service = ref.read(tanglexServiceProvider);
    try {
      if (!service.isInitialized) {
        await service.initialize();
      }
      if (!mounted) return;
      setState(() {
        _status = _CoreStatus.ready;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _CoreStatus.failed;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TangleX',
                  style: text.displaySmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'UI not implemented yet',
                  style: text.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                _CoreStatusChip(status: _status, error: _error),
                if (_status == _CoreStatus.failed) ...[
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() {
                        _status = _CoreStatus.initializing;
                        _error = null;
                      });
                      _bootCore();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoreStatusChip extends StatelessWidget {
  const _CoreStatusChip({required this.status, required this.error});

  final _CoreStatus status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    final Widget icon;
    final String label;
    switch (status) {
      case _CoreStatus.initializing:
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        icon = SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: fg),
        );
        label = 'Core initializing…';
        break;
      case _CoreStatus.ready:
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
        icon = Icon(Icons.check_circle_rounded, size: 16, color: fg);
        label = 'Core ready';
        break;
      case _CoreStatus.failed:
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        icon = Icon(Icons.error_rounded, size: 16, color: fg);
        label = error == null || error!.isEmpty
            ? 'Core failed'
            : 'Core failed: $error';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: ShapeDecoration(
        color: bg,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
