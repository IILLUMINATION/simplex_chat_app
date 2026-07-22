import 'dart:io';
import 'package:flutter/material.dart';

import '../../../../domain/chat_models.dart';
import '../../theme/tx_theme.dart';
import '../tx_message_renderer.dart';

class ImageMessageRenderer implements TxMessageRenderer {
  @override
  String get messageType => 'image';

  @override
  bool canRender(UiMessage message) {
    return !message.isSystem &&
        message.images.isNotEmpty &&
        !message.images.first.isSticker &&
        !message.images.first.isCircle;
  }

  @override
  Widget buildContent(TxMessageRenderContext renderContext) {
    final ctx = renderContext.context;
    final msg = renderContext.message;
    final isMe = renderContext.isMe;
    final theme = ctx.txTheme;
    final img = msg.images.first;

    final Widget imageWidget;
    if (img.filePath != null && File(img.filePath!).existsSync()) {
      imageWidget = Image.file(
        File(img.filePath!),
        fit: BoxFit.cover,
      );
    } else if (img.bytes != null && img.bytes!.isNotEmpty) {
      imageWidget = Image.memory(
        img.bytes!,
        fit: BoxFit.cover,
      );
    } else {
      imageWidget = Container(
        height: 150,
        color: Colors.black26,
        child: const Center(child: Icon(Icons.image_not_supported_rounded)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: imageWidget,
          ),
        ),
        if (msg.text.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            msg.text,
            style: TextStyle(
              color: isMe ? theme.myBubbleFg : theme.peerBubbleFg,
              fontSize: 15,
            ),
          ),
        ],
      ],
    );
  }
}
