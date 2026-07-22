// TangleX — message bubble (text-only for MVP).
//
// MD3 tonal bubble. Outgoing messages use `primaryContainer`; incoming use
// `surfaceContainerHighest`. System messages render as a small pill in the
// center of the row. Media / voice / stickers come in later milestones.

import 'package:flutter/material.dart';

import '../../../../domain/chat_models.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final UiMessage message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (message.isSystem) {
      return _SystemPill(text: message.text);
    }

    final fromMe = message.fromMe;
    final bg = fromMe ? cs.primaryContainer : cs.surfaceContainerHighest;
    final fg = fromMe ? cs.onPrimaryContainer : cs.onSurface;
    final radius = const Radius.circular(20);

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: radius,
          topRight: radius,
          bottomLeft: fromMe ? radius : const Radius.circular(4),
          bottomRight: fromMe ? const Radius.circular(4) : radius,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.quoted != null)
            _QuotedBlock(quoted: message.quoted!, fromMe: fromMe),
          if (message.text.isNotEmpty)
            Text(
              message.text,
              style: tt.bodyLarge?.copyWith(color: fg),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.timeStr,
                  style: tt.labelSmall?.copyWith(
                    color: fg.withValues(alpha: 0.75),
                  ),
                ),
                if (fromMe && message.status.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _statusIcon(message.status, fg.withValues(alpha: 0.75)),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        mainAxisAlignment:
            fromMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [bubble],
      ),
    );
  }

  Widget _statusIcon(String status, Color color) {
    IconData? icon;
    switch (status) {
      case 'sndSent':
        icon = Icons.done_rounded;
        break;
      case 'sndRcvd':
        icon = Icons.done_all_rounded;
        break;
      case 'sndNew':
      case 'sndPending':
        icon = Icons.schedule_rounded;
        break;
      case 'sndErrorAuth':
      case 'sndError':
        icon = Icons.error_outline_rounded;
        break;
    }
    if (icon == null) return const SizedBox.shrink();
    return Icon(icon, size: 14, color: color);
  }
}

class _QuotedBlock extends StatelessWidget {
  const _QuotedBlock({required this.quoted, required this.fromMe});

  final QuotedMessage quoted;
  final bool fromMe;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = fromMe ? cs.onPrimaryContainer : cs.primary;
    final fg = fromMe ? cs.onPrimaryContainer : cs.onSurface;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent, width: 3)),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        color: accent.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quoted.senderName.isNotEmpty)
            Text(
              quoted.senderName,
              style: tt.labelMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          Text(
            quoted.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(color: fg.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}

class _SystemPill extends StatelessWidget {
  const _SystemPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            text,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
