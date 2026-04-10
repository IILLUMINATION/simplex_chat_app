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

  void _showSnackBar(String message, bool success) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? cs.onInverseSurface : cs.error,
      ),
    );
  }

  Future<void> _connectViaLink() async {
    final link = _linkController.text.trim();
    if (link.isEmpty) return;

    final service = ref.read(tanglexServiceProvider);
    final loc = AppLocalizations.of(context);

    if (!service.isInitialized) {
      _showSnackBar(loc.translate('core_not_initialized_yet'), false);
      return;
    }

    setState(() => _connecting = true);
    final success = await service.connectViaLink(link);
    setState(() => _connecting = false);

    if (mounted) {
      _showSnackBar(
        success ? loc.translate('connection_request_sent') : loc.translate('failed_connect'),
        success,
      );
      if (success) _linkController.clear();
    }
  }

  Future<void> _createMyLink() async {
    setState(() => _loadingLink = true);
    final service = ref.read(tanglexServiceProvider);
    final loc = AppLocalizations.of(context);

    if (!service.isInitialized) {
      if (mounted) {
        setState(() => _loadingLink = false);
        _showSnackBar(loc.translate('core_not_initialized_yet'), false);
      }
      return;
    }

    final link = await service.createConnectionLink();
    setState(() {
      _myLink = link;
      _loadingLink = false;
    });

    if (mounted && link == null) {
      _showSnackBar(loc.translate('failed_create_link'), false);
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
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.link, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            loc.translate('paste_link_description'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: loc.translate('connection_link_label'),
              hintText: 'smp://...',
              border: const OutlineInputBorder(),
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
            label: Text(loc.translate('connect_button')),
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
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.share, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          Text(
            loc.translate('create_link_description'),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.outline),
          ),
          const SizedBox(height: 24),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (myLink == null)
            FilledButton.icon(
              onPressed: onCreateLink,
              icon: const Icon(Icons.add_link),
              label: Text(loc.translate('create_my_link')),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.primaryContainer),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.translate('your_link'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
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
                              SnackBar(content: Text(loc.translate('link_copied'))),
                            );
                          },
                          icon: const Icon(Icons.copy),
                          label: Text(loc.translate('copy')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            // TODO: share
                          },
                          icon: const Icon(Icons.share),
                          label: Text(loc.translate('share')),
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
