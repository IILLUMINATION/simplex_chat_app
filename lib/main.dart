import 'package:flutter/material.dart';

import 'src/service/simplex_service.dart';

void main() {
  runApp(const SimplexApp());
}

class SimplexApp extends StatelessWidget {
  const SimplexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimpleX FFI Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0C7D69)),
      ),
      home: const SimplexHomePage(),
    );
  }
}

class SimplexHomePage extends StatefulWidget {
  const SimplexHomePage({super.key});

  @override
  State<SimplexHomePage> createState() => _SimplexHomePageState();
}

class _SimplexHomePageState extends State<SimplexHomePage> {
  late final SimplexService _service;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = SimplexService();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _initCore() async {
    setState(() => _busy = true);
    try {
      await _service.initialize();
    } catch (_) {
      // Error is already written to on-screen logs by the service.
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _sendTestCommand() async {
    setState(() => _busy = true);
    try {
      await _service.sendTestCommand();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SimpleX Core Test')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _busy ? null : _initCore,
                      child: const Text('Init Core'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _busy ? null : _sendTestCommand,
                      child: const Text('Send Test Command'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ValueListenableBuilder<List<String>>(
                    valueListenable: _service.logs,
                    builder: (context, logs, _) {
                      if (logs.isEmpty) {
                        return const Center(
                          child: Text('Logs will appear here...'),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(logs[index]),
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
      ),
    );
  }
}
