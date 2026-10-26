import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../service/tanglex_service.dart';

/// One [TanglexService] per process, shared by the legacy screens and the
/// new shell.
final tanglexServiceProvider = Provider<TanglexService>((ref) {
  final service = TanglexService();
  ref.onDispose(() => service.dispose());
  return service;
});
