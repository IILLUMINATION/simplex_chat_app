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

/// Global Riverpod provider for the FFI-backed SimpleX service.
///
/// Disposed automatically with the [ProviderScope] that hosts the app.
final tanglexServiceProvider = Provider<TanglexService>((ref) {
  final service = TanglexService();
  ref.onDispose(service.dispose);
  return service;
});

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: TangleXApp()));
}
