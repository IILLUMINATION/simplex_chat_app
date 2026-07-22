import 'package:flutter/foundation.dart';
import '../../../domain/chat_models.dart';
import 'tx_message_renderer.dart';

/// Глобальный реестр UI-плагинов и рендереров TangleX
class TxPluginRegistry {
  TxPluginRegistry._();
  static final TxPluginRegistry instance = TxPluginRegistry._();

  final Map<String, TxMessageRenderer> _renderers = {};

  /// Зарегистрировать новый рендерер сообщений
  void registerRenderer(TxMessageRenderer renderer) {
    _renderers[renderer.messageType] = renderer;
    debugPrint('[TxPluginRegistry] Registered renderer: ${renderer.messageType}');
  }

  /// Найти подходящий рендерер для сообщения
  TxMessageRenderer? getRenderer(UiMessage message) {
    // 1. Попытка найти прямой рендерер по типу
    for (final renderer in _renderers.values) {
      if (renderer.canRender(message)) {
        return renderer;
      }
    }
    return null;
  }
}
