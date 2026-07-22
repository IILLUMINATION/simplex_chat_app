// TangleX — compose bar.
//
// Material 3 text input + send IconButton.  When the contact handshake is
// not finished, the input is disabled and a hint is shown above it
// (HANDOFF.md § 8 point 4).

import 'package:flutter/material.dart';

import '../../../../localization/app_localizations.dart';

class ComposeBar extends StatefulWidget {
  const ComposeBar({
    super.key,
    required this.onSend,
    required this.enabled,
    required this.sending,
  });

  final Future<bool> Function(String text) onSend;
  final bool enabled;
  final bool sending;

  @override
  State<ComposeBar> createState() => _ComposeBarState();
}

class _ComposeBarState extends State<ComposeBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final text = _controller.text;
    if (text.trim().isEmpty || widget.sending) return;
    final ok = await widget.onSend(text);
    if (!mounted) return;
    if (ok) {
      _controller.clear();
      setState(() => _hasText = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final t = AppLocalizations.of(context);
    final canSend = widget.enabled && _hasText && !widget.sending;

    return Material(
      color: cs.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.enabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    t.translate('chat_wait_send'),
                    style: tt.bodySmall?.copyWith(color: cs.tertiary),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: widget.enabled && !widget.sending,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: t.translate('message_placeholder'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: canSend ? _handleSend : null,
                    icon: widget.sending
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: cs.onPrimary,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
