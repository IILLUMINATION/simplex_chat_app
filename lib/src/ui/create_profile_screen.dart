// "Create profile" screen — used both for the very first profile and for
// subsequent additional profiles from Profile screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_localizations.dart';
import '../service/tanglex_service.dart';
import 'design/design.dart';

class CreateProfileScreen extends ConsumerStatefulWidget {
  const CreateProfileScreen({super.key, required this.service});

  final TanglexService service;

  @override
  ConsumerState<CreateProfileScreen> createState() =>
      _CreateProfileScreenState();
}

class _CreateProfileScreenState extends ConsumerState<CreateProfileScreen> {
  final _displayNameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _shortDescrController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _displayNameController.dispose();
    _fullNameController.dispose();
    _shortDescrController.dispose();
    super.dispose();
  }

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
    });

    final response = await widget.service.createUserProfile(
      displayName: displayName,
      fullName: _fullNameController.text.trim(),
      shortDescr: _shortDescrController.text.trim().isEmpty
          ? null
          : _shortDescrController.text.trim(),
    );

    if (!mounted) return;
    final hasError = response == null || response.containsKey('error');
    setState(() {
      _busy = false;
      if (hasError) {
        _error = response?['error']?.toString() ??
            loc.translate('initialization_error');
      }
    });

    if (!hasError) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(loc.translate('create_profile'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _displayNameController,
              decoration: InputDecoration(
                labelText: loc.translate('display_name'),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppSpacing.s3),
            TextField(
              controller: _fullNameController,
              decoration: InputDecoration(
                labelText: loc.translate('full_name'),
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            TextField(
              controller: _shortDescrController,
              decoration: InputDecoration(
                labelText: loc.translate('bio'),
                hintText: loc.translate('bio_hint'),
              ),
              maxLength: 160,
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.s4),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.s3),
                margin: const EdgeInsets.only(bottom: AppSpacing.s4),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.15),
                  borderRadius: AppRadius.brs,
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.5),
                  ),
                ),
                child: SelectableText(
                  _error!,
                  style: AppText.caption.copyWith(color: AppColors.error),
                ),
              ),
            AppPrimaryButton(
              label: loc.translate('create'),
              icon: Icons.person_add_rounded,
              onPressed: _busy ? null : _createProfile,
              expand: true,
              loading: _busy,
            ),
          ],
        ),
      ),
    );
  }
}
