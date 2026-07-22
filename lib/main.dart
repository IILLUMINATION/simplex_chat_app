// TangleX — entry point.
//
// Boots Flutter, wires the Riverpod ProviderScope, and mounts the app shell
// from `lib/src/ui/app/app.dart`.  All UI lives under `lib/src/ui/`.
//
// Per HANDOFF.md § 12, `tanglexServiceProvider` is the single global handle
// to the FFI service; it is disposed automatically by the ProviderScope.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/service/tanglex_service.dart';
import 'src/ui/app/app.dart';
import 'src/ui/core/plugins/renderers/text_message_renderer.dart';
import 'src/ui/core/plugins/tx_plugin_registry.dart';

/// Global Riverpod provider for the FFI-backed SimpleX service.
///
/// Disposed automatically with the [ProviderScope] that hosts the app.
final tanglexServiceProvider = Provider<TanglexService>((ref) {
  final service = TanglexService();
  ref.onDispose(service.dispose);
  return service;
});

void _setupPlugins() {
  // Регистрируем встроенные рендереры сообщений
  final registry = TxPluginRegistry.instance;
  registry.registerRenderer(TextMessageRenderer());
  // Сюда же позже добавим: ImageRenderer, VoiceRenderer, CircleVideoRenderer, StickerRenderer
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _setupPlugins();
  runApp(const ProviderScope(child: TangleXApp()));
}
