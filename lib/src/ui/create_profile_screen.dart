import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_localizations.dart';
import '../service/tanglex_service.dart';

class CreateProfileScreen extends ConsumerStatefulWidget {
  final TanglexService service;

  const CreateProfileScreen({super.key, required this.service});

  @override
  ConsumerState<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends ConsumerState<CreateProfileScreen> {
  final _displayNameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _shortDescrController = TextEditingController();
  bool _busy = false;
  String? _result;
  String? _error;

  Future<void> _createProfile() async {
    final loc = AppLocalizations.of(context);
    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) {
      setState(() => _error = loc.translate('display_name_required'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });

    final response = await widget.service.createUserProfile(
      displayName: displayName,
      fullName: _fullNameController.text.trim(),
      shortDescr: _shortDescrController.text.trim().isEmpty
          ? null
          : _shortDescrController.text.trim(),
    );

    setState(() {
      _busy = false;
      if (response != null) {
        _result = response.toString();
        if (response.containsKey('error')) {
          _error = response['error']?.toString() ?? _result;
        }
      }
    });
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _fullNameController.dispose();
    _shortDescrController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.translate('create_profile')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _displayNameController,
              decoration: InputDecoration(
                labelText: loc.translate('display_name'),
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _fullNameController,
              decoration: InputDecoration(
                labelText: loc.translate('full_name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _shortDescrController,
              decoration: InputDecoration(
                labelText: loc.translate('bio'),
                hintText: loc.translate('bio_hint'),
                border: const OutlineInputBorder(),
              ),
              maxLength: 160,
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.errorContainer),
                ),
                child: SelectableText(
                  _error!,
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _createProfile,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add),
                label: Text(loc.translate('create')),
              ),
            ),
            if (_result != null && _error == null) ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
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
                      loc.translate('profile_created'),
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _result!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
