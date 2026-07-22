import 'package:flutter/material.dart';

import '../../../../domain/chat_models.dart';
import '../../../core/plugins/tx_message_renderer.dart';
import '../../../core/plugins/tx_plugin_registry.dart';
import '../../../core/theme/tx_theme.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onTap,
    this.onLongPress,
    this.onSwipeToReply,
  });

  final UiMessage message;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSwipeToReply;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return _SystemPill(text: message.text);
    }

    final theme = context.txTheme;
    final fromMe = message.fromMe;

    // Выбираем фоновые цвета из нашей расширенной темы
    final bg = fromMe ? theme.myBubbleBg : theme.peerBubbleBg;
    final gradient = fromMe ? theme.myBubbleGradient : theme.peerBubbleGradient;
    final fg = fromMe ? theme.myBubbleFg : theme.peerBubbleFg;

    // Ищем подходящий рендерер в плагинах
    final renderer = TxPluginRegistry.instance.getRenderer(message);

    // Расчёт скругления углов с учётом стиля бабблов (Telegram / Material3)
    final radius = Radius.circular(theme.bubbleRadius);
    final isTelegramStyle = theme.bubbleStyle == TxBubbleStyle.telegram;

    final borderRadius = BorderRadius.only(
      topLeft: radius,
      topRight: radius,
      bottomLeft: fromMe ? radius : (isTelegramStyle ? Radius.zero : const Radius.circular(4)),
      bottomRight: fromMe ? (isTelegramStyle ? Radius.zero : const Radius.circular(4)) : radius,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        mainAxisAlignment:
            fromMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: GestureDetector(
              onTap: onTap,
              onLongPress: onLongPress,
                child: IntrinsicWidth(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.78,
                    ),
                    decoration: BoxDecoration(
                      color: gradient == null ? bg : null,
                      gradient: gradient,
                      borderRadius: borderRadius,
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Блок цитируемого сообщения (если это ответ)
                        if (message.quoted != null)
                          _QuotedBlock(quoted: message.quoted!, fromMe: fromMe),

                        // Содержимое, отрисованное зарегистрированным плагином
                        if (renderer != null)
                          renderer.buildContent(
                            TxMessageRenderContext(
                              context: context,
                              message: message,
                              isMe: fromMe,
                            ),
                          )
                        else
                          // Фолбэк, если плагин для редкого типа сообщения ещё не зарегистрирован
                          Text(
                            message.text,
                            style: TextStyle(color: fg),
                          ),

                        const SizedBox(height: 2),

                        // Время и статус сообщения (галочки)
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                message.timeStr,
                                style: TextStyle(
                                  color: theme.timeTextColor,
                                  fontSize: 11,
                                ),
                              ),
                              if (fromMe && message.status.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                _StatusIcon(status: message.status, color: theme.timeTextColor),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Блок цитаты
class _QuotedBlock extends StatelessWidget {
  const _QuotedBlock({required this.quoted, required this.fromMe});

  final QuotedMessage quoted;
  final bool fromMe;

  @override
  Widget build(BuildContext context) {
    final theme = context.txTheme;
    final accent = theme.quoteBorderColor;
    final fg = fromMe ? theme.myBubbleFg : theme.peerBubbleFg;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent, width: 3)),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        color: accent.withValues(alpha: 0.12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quoted.senderName.isNotEmpty)
            Text(
              quoted.senderName,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          Text(
            quoted.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg.withValues(alpha: 0.9),
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Иконка статуса отправки (Галочки)
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status, required this.color});

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
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

/// Системная плашка (например, "Чат начат")
class _SystemPill extends StatelessWidget {
  const _SystemPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
