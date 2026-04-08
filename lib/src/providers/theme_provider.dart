import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'persistent_store.dart';

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

enum AppThemeMode {
  light,
  dark,
  system;

  static AppThemeMode fromName(String name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return AppThemeMode.system;
  }

  ThemeMode get flutterMode => switch (this) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      };
}

class ThemeNotifier extends StateNotifier<ThemeConfigData> {
  ThemeNotifier() : super(const ThemeConfigData()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('theme_config');
    if (raw != null) {
      try {
        state = ThemeConfigData.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
  }

  Future<void> setTheme(AppTheme theme) async {
    state = state.copyWith(theme: theme.name);
    await _save();
  }

  Future<void> setMode(AppThemeMode mode) async {
    state = state.copyWith(mode: mode.name);
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_config', jsonEncode(state.toJson()));
  }

  ThemeData get lightTheme => _buildLightTheme(AppTheme.fromName(state.theme));
  ThemeData get darkTheme => _buildDarkTheme(AppTheme.fromName(state.theme));
}

final themeNotifierProvider =
    StateNotifierProvider<ThemeNotifier, ThemeConfigData>((ref) {
  return ThemeNotifier();
});

// ===== Themes =====
ThemeData _buildLightTheme(AppTheme theme) => switch (theme) {
      AppTheme.nord => _nordLight,
      AppTheme.amoled => _amoledLight,
      AppTheme.solarized => _solarizedLight,
      AppTheme.material => _materialLight,
    };

ThemeData _buildDarkTheme(AppTheme theme) => switch (theme) {
      AppTheme.nord => _nordDark,
      AppTheme.amoled => _amoledDark,
      AppTheme.solarized => _solarizedDark,
      AppTheme.material => _materialDark,
    };

ThemeData get _materialLight => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0C7D69)),
      useMaterial3: true,
    );

ThemeData get _materialDark => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0C7D69),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

ThemeData get _nordLight => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5E81AC),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      fontFamily: 'Inter',
    );

ThemeData get _nordDark => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5E81AC),
        brightness: Brightness.dark,
        surface: const Color(0xFF3B4252),
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF2E3440),
      fontFamily: 'Inter',
    );

ThemeData get _amoledLight => _materialLight;

ThemeData get _amoledDark => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0C7D69),
        brightness: Brightness.dark,
        surface: const Color(0xFF0A0A0A),
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.black,
    );

ThemeData get _solarizedLight => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB58900),
        brightness: Brightness.light,
        surface: const Color(0xFFEEE8D5),
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFFDF6E3),
    );

ThemeData get _solarizedDark => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB58900),
        brightness: Brightness.dark,
        surface: const Color(0xFF073642),
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF002B36),
    );
