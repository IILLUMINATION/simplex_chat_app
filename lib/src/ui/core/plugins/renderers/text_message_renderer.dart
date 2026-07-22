import 'package:flutter/material.dart';
import '../../../../domain/chat_models.dart';
import '../../theme/tx_theme.dart';
import '../tx_message_renderer.dart';

class TextMessageRenderer implements TxMessageRenderer {
  @override
  String get messageType => 'text';

  @override
  bool canRender(UiMessage message) {
    // Рендерим как текст, если нет специфичных медиа/аудио и есть текст
    return !message.isSystem &&
        message.images.isEmpty &&
        message.audio == null &&
        message.text.isNotEmpty;
  }

  @override
  Widget buildContent(TxMessageRenderContext renderContext) {
    final ctx = renderContext.context;
    final msg = renderContext.message;
    final isMe = renderContext.isMe;
    final theme = ctx.txTheme;
    final textColor = isMe ? theme.myBubbleFg : theme.peerBubbleFg;

    return Text(
      msg.text,
      style: TextStyle(
        color: textColor,
        fontSize: 15.5,
        height: 1.3,
      ),
    );
  }
}
