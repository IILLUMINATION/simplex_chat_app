import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart';
import '../localization/app_localizations.dart';

class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  final TextEditingController _cmdController = TextEditingController();

  Future<void> _initCore() async {
    try {
      final service = ref.read(simplexServiceProvider);
      await service.initialize();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Init error: $e')),
        );
      }
    }
  }

  Future<void> _sendCommand() async {
    final cmd = _cmdController.text.trim();
    if (cmd.isEmpty) return;
    _cmdController.clear();

    final service = ref.read(simplexServiceProvider);
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
    final service = ref.watch(simplexServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Console'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Init button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _initCore,
                icon: const Icon(Icons.play_arrow),
                label: Text(loc.translate('init_core')),
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
                  border: Border.all(color: Colors.grey),
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
