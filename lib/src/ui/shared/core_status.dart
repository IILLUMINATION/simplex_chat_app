// TangleX — bootstrap gate.
//
// Wraps the app shell so nothing tries to call TanglexService methods before
// `initialize()` resolves. Replaces the throwaway `BootstrapScreen` from
// main.dart per HANDOFF.md § 3.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../../localization/app_localizations.dart';

/// FutureProvider that resolves when the FFI service has booted.
///
/// We avoid `AsyncValue<void>` here — returning `bool` lets us distinguish
/// the (rare) post-init reboot path cleanly.
final coreInitProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(tanglexServiceProvider);
  if (service.isInitialized) return true;
  await service.initialize();
  return true;
});

/// Shows [child] only once the core is ready. While initializing, displays a
/// centered progress indicator; on failure, shows an error card with a Retry.
class CoreBootGate extends ConsumerWidget {
  const CoreBootGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(coreInitProvider);
    return boot.when(
      data: (_) => child,
      loading: () => const _BootLoading(),
      error: (err, _) => _BootError(error: err.toString(), ref: ref),
    );
  }
}

class _BootLoading extends StatelessWidget {
  const _BootLoading();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'TangleX',
                style: tt.headlineMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

class _BootError extends StatelessWidget {
  const _BootError({required this.error, required this.ref});

  final String error;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_rounded, size: 48, color: cs.error),
                const SizedBox(height: 16),
                Text(
                  t.translate('initialization_error'),
                  style: tt.titleLarge?.copyWith(color: cs.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FilledButton.tonalIcon(
                  onPressed: () => ref.invalidate(coreInitProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(t.translate('initialize')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
