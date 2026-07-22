import 'dart:io';
import 'package:flutter/material.dart';

import '../../../../domain/chat_models.dart';
import '../tx_message_renderer.dart';

class StickerMessageRenderer implements TxMessageRenderer {
  @override
  String get messageType => 'sticker';

  @override
  bool canRender(UiMessage message) {
    return !message.isSystem &&
        message.images.isNotEmpty &&
        message.images.first.isSticker;
  }

  @override
  Widget buildContent(TxMessageRenderContext renderContext) {
    final msg = renderContext.message;
    final img = msg.images.first;

    final Widget stickerWidget;
    if (img.filePath != null && File(img.filePath!).existsSync()) {
      stickerWidget = Image.file(File(img.filePath!), fit: BoxFit.contain);
    } else if (img.bytes != null && img.bytes!.isNotEmpty) {
      stickerWidget = Image.memory(img.bytes!, fit: BoxFit.contain);
    } else {
      stickerWidget = const Icon(Icons.sticky_note_2_rounded, size: 100);
    }

    return SizedBox(
      width: 160,
      height: 160,
      child: stickerWidget,
    );
  }
}
