// Telegram Style Compose Bar

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final t = AppLocalizations.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Текстовое поле в стиле Telegram
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Кнопка GIF / Emoji
                    IconButton(
                      icon: const Text(
                        'GIF',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      onPressed: () {},
                    ),

                    // Поле ввода
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.enter): () {
                            _handleSend();
                          },
                          const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
                            _handleSend();
                          },
                        },
                        child: TextField(
                          controller: _controller,
                          enabled: widget.enabled && !widget.sending,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _handleSend(),
                          decoration: InputDecoration(
                            hintText: t.translate('message_placeholder'),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ),

                    // Иконка скрепки (Прикрепить)
                    IconButton(
                      icon: const Icon(Icons.attach_file_rounded),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Круглая синяя кнопка (Отправка / Микрофон)
            GestureDetector(
              onTap: _hasText ? _handleSend : null,
              child: CircleAvatar(
                radius: 22,
                backgroundColor: cs.primary,
                child: widget.sending
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onPrimary,
                        ),
                      )
                    : Icon(
                        _hasText ? Icons.send_rounded : Icons.mic_rounded,
                        color: cs.onPrimary,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
