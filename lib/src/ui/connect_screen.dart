import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart';
import '../localization/app_localizations.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _linkController = TextEditingController();
  bool _connecting = false;
  String? _myLink;
  bool _loadingLink = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _connectViaLink() async {
    final link = _linkController.text.trim();
    if (link.isEmpty) return;

    final service = ref.read(simplexServiceProvider);
    if (!service.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Core is not initialized yet'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _connecting = true);
    final success = await service.connectViaLink(link);

    setState(() => _connecting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Connection request sent!'
                : 'Failed to connect. Check the logs for details.',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      if (success) _linkController.clear();
    }
  }

  Future<void> _createMyLink() async {
    setState(() => _loadingLink = true);
    final service = ref.read(simplexServiceProvider);

    if (!service.isInitialized) {
      if (mounted) {
        setState(() => _loadingLink = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Core is not initialized yet'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final link = await service.createConnectionLink();

    setState(() {
      _myLink = link;
      _loadingLink = false;
    });

    if (mounted && link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create link. Check the logs for details.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.qr_code_scanner),
              text: loc.translate('connect_by_link'),
            ),
            Tab(
              icon: const Icon(Icons.share),
              text: loc.translate('my_link'),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _ConnectByLinkTab(
                controller: _linkController,
                connecting: _connecting,
                onConnect: _connectViaLink,
              ),
              _MyLinkTab(
                myLink: _myLink,
                loading: _loadingLink,
                onCreateLink: _createMyLink,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectByLinkTab extends StatelessWidget {
  final TextEditingController controller;
  final bool connecting;
  final VoidCallback onConnect;

  const _ConnectByLinkTab({
    required this.controller,
    required this.connecting,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.link, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Paste a connection link from your contact to start a conversation.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Connection link',
              hintText: 'smp://...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: connecting ? null : onConnect,
            icon: connecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add),
            label: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

class _MyLinkTab extends StatelessWidget {
  final String? myLink;
  final bool loading;
  final VoidCallback onCreateLink;

  const _MyLinkTab({
    required this.myLink,
    required this.loading,
    required this.onCreateLink,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.share, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Create your connection link and share it with anyone you want to chat with.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (myLink == null)
            FilledButton.icon(
              onPressed: onCreateLink,
              icon: const Icon(Icons.add_link),
              label: const Text('Create my link'),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your link:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    myLink!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: myLink!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Link copied!')),
                            );
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            // TODO: share
                          },
                          icon: const Icon(Icons.share),
                          label: const Text('Share'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
