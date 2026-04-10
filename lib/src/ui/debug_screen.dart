import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart';
import '../localization/app_localizations.dart';

class DebugScreenWrapper extends ConsumerStatefulWidget {
  const DebugScreenWrapper({super.key});

  @override
  ConsumerState<DebugScreenWrapper> createState() => _DebugScreenWrapperState();
}

class _DebugScreenWrapperState extends ConsumerState<DebugScreenWrapper> {
  final TextEditingController _cmdController = TextEditingController();
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    _autoInitCore();
  }

  Future<void> _autoInitCore() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final service = ref.read(tanglexServiceProvider);
      if (!service.isInitialized) {
        await service.initialize();
      }
    } catch (e) {
      // Errors are logged by service
    } finally {
      _initializing = false;
    }
  }

  Future<void> _sendCommand() async {
    final cmd = _cmdController.text.trim();
    if (cmd.isEmpty) return;
    _cmdController.clear();

    final service = ref.read(tanglexServiceProvider);
    await service.sendCommand(cmd);
  }

  @override
  void dispose() {
    _cmdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final service = ref.watch(tanglexServiceProvider);
    final cs = Theme.of(context).colorScheme;
    final isReady = service.isInitialized;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.translate('debug_console')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Status indicator
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isReady
                    ? cs.primaryContainer.withOpacity(0.3)
                    : cs.tertiaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isReady ? cs.primaryContainer : cs.tertiaryContainer,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isReady ? Icons.check_circle : Icons.hourglass_top,
                    size: 20,
                    color: isReady ? cs.onPrimaryContainer : cs.onTertiaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isReady
                        ? loc.translate('core_initialized')
                        : loc.translate('initializing'),
                    style: TextStyle(
                      color: isReady ? cs.onPrimaryContainer : cs.onTertiaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Command input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cmdController,
                    decoration: InputDecoration(
                      labelText: loc.translate('command_label'),
                      hintText: loc.translate('command_hint'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendCommand(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _sendCommand,
                  icon: const Icon(Icons.send),
                  label: Text(loc.translate('send')),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Logs
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: service.logs,
                  builder: (context, logs, _) {
                    if (logs.isEmpty) {
                      return Center(child: Text(loc.translate('logs_here')));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: logs.length,
                      itemBuilder: (context, i) {
                        return SelectableText(
                          logs[i],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        );
                      },
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
