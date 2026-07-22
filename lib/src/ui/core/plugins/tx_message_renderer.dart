import 'package:flutter/material.dart';
import '../../../domain/chat_models.dart';

/// Контекст для рендеринга сообщения
class TxMessageRenderContext {
  const TxMessageRenderContext({
    required this.context,
    required this.message,
    required this.isMe,
  });

  final BuildContext context;
  final UiMessage message;
  final bool isMe;
}

/// Абстрактный рендерер типа сообщения.
/// Каждый плагин/тип содержимого реализует этот класс.
abstract class TxMessageRenderer {
  /// Идентификатор типа сообщения (например, 'text', 'image', 'voice', 'poll', 'code')
  String get messageType;

  /// Можем ли мы отрендерить это сообщение
  bool canRender(UiMessage message);

  /// Отрисовка контента внутри баббла
  Widget buildContent(TxMessageRenderContext renderContext);
}
