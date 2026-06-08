// Developer console: free-form FFI command input + scrolling logs.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart';
import '../localization/app_localizations.dart';
import 'design/design.dart';

class DebugScreenWrapper extends ConsumerStatefulWidget {
  const DebugScreenWrapper({super.key});

  @override
  ConsumerState<DebugScreenWrapper> createState() =>
      _DebugScreenWrapperState();
}

class _DebugScreenWrapperState extends ConsumerState<DebugScreenWrapper> {
  final TextEditingController _cmdController = TextEditingController();
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    _autoInitCore();
  }

  @override
  void dispose() {
    _cmdController.dispose();
    super.dispose();
  }

  Future<void> _autoInitCore() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final service = ref.read(tanglexServiceProvider);
      if (!service.isInitialized) {
        await service.initialize();
      }
    } catch (_) {
      // Errors are surfaced through service.logs.
    } finally {
      _initializing = false;
    }
  }

  Future<void> _sendCommand() async {
    final cmd = _cmdController.text.trim();
    if (cmd.isEmpty) return;
    _cmdController.clear();
    await ref.read(tanglexServiceProvider).sendCommand(cmd);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final service = ref.watch(tanglexServiceProvider);
    final isReady = service.isInitialized;

    return Scaffold(
      appBar: AppBar(title: Text(loc.translate('debug_console'))),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.s3),
        child: Column(
          children: [
            _StatusChip(isReady: isReady, loc: loc),
            const SizedBox(height: AppSpacing.s3),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cmdController,
                    decoration: InputDecoration(
                      labelText: loc.translate('command_label'),
                      hintText: loc.translate('command_hint'),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendCommand(),
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                AppPrimaryButton(
                  label: loc.translate('send'),
                  icon: Icons.send_rounded,
                  onPressed: _sendCommand,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s3),

            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  border: Border.all(color: AppColors.border),
                  borderRadius: AppRadius.brm,
                ),
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: service.logs,
                  builder: (context, logs, _) {
                    if (logs.isEmpty) {
                      return Center(
                        child: Text(
                          loc.translate('logs_here'),
                          style: AppText.caption,
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.s3),
                      itemCount: logs.length,
                      itemBuilder: (context, i) => SelectableText(
                        logs[i],
                        style: AppText.code.copyWith(fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isReady, required this.loc});

  final bool isReady;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final color = isReady ? AppColors.success : AppColors.warning;
    final icon = isReady
        ? Icons.check_circle_rounded
        : Icons.hourglass_top_rounded;
    final label = isReady
        ? loc.translate('core_initialized')
        : loc.translate('initializing');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppRadius.brs,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: AppIconSize.small, color: color),
          const SizedBox(width: AppSpacing.s2),
          Text(
            label,
            style: AppText.captionEmph.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
