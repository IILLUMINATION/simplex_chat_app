// TangleX is dark-only. This provider stays as a thin compatibility layer so
// that the rest of the app can keep using `themeNotifierProvider` while we
// migrate, but every theme variant returns the same dark ThemeData built from
// design tokens (see lib/src/ui/design/).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/design/theme.dart';
import 'persistent_store.dart';

/// Kept for backwards-compatibility with persisted `theme_config` blobs.
/// All variants resolve to the single dark theme.
enum AppTheme {
  material,
  nord,
  amoled,
  solarized;

  static AppTheme fromName(String name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return AppTheme.material;
  }
}

/// Kept for backwards-compatibility. Always resolves to dark.
enum AppThemeMode {
  light,
  dark,
  system;

  static AppThemeMode fromName(String name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return AppThemeMode.dark;
  }

  ThemeMode get flutterMode => ThemeMode.dark;
}

class ThemeNotifier extends StateNotifier<ThemeConfigData> {
  ThemeNotifier() : super(const ThemeConfigData(mode: 'dark'));

  // No-op setters kept to avoid breaking call sites during migration.
  Future<void> setTheme(AppTheme theme) async {}
  Future<void> setMode(AppThemeMode mode) async {}

  ThemeData get lightTheme => buildAppTheme();
  ThemeData get darkTheme => buildAppTheme();
}

final themeNotifierProvider =
    StateNotifierProvider<ThemeNotifier, ThemeConfigData>((ref) {
  return ThemeNotifier();
});
