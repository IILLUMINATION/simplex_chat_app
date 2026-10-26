import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_metrics.dart';
import 'app_palette.dart';
import 'app_theme.dart';
import 'app_typography.dart';

enum AppThemePreset {
  classic,
  blue,
  amoled;

  static AppThemePreset fromName(String? name) => values.firstWhere(
        (p) => p.name == name,
        orElse: () => AppThemePreset.classic,
      );
}

/// User-facing theme knobs, mirroring Telegram's appearance settings.
@immutable
class AppThemeSettings {
  const AppThemeSettings({
    this.mode = ThemeMode.system,
    this.preset = AppThemePreset.classic,
    this.accent,
    this.bubbleRadius = 16,
    this.fontScale = 1.0,
    this.fontFamily,
    this.bubbleIn,
    this.bubbleOut,
    this.wallpaper,
  });

  final ThemeMode mode;
  final AppThemePreset preset;
  final Color? accent;
  final double bubbleRadius;
  final double fontScale;
  final String? fontFamily;
  final Color? bubbleIn;
  final Color? bubbleOut;
  final Color? wallpaper;

  static const double minBubbleRadius = 0;
  static const double maxBubbleRadius = 20;
  static const double minFontScale = 0.85;
  static const double maxFontScale = 1.35;

  AppThemeSettings copyWith({
    ThemeMode? mode,
    AppThemePreset? preset,
    Color? accent,
    bool clearAccent = false,
    double? bubbleRadius,
    double? fontScale,
    String? fontFamily,
    Color? bubbleIn,
    bool clearBubbleIn = false,
    Color? bubbleOut,
    bool clearBubbleOut = false,
    Color? wallpaper,
    bool clearWallpaper = false,
  }) =>
      AppThemeSettings(
        mode: mode ?? this.mode,
        preset: preset ?? this.preset,
        accent: clearAccent ? null : (accent ?? this.accent),
        bubbleRadius: bubbleRadius ?? this.bubbleRadius,
        fontScale: fontScale ?? this.fontScale,
        fontFamily: fontFamily ?? this.fontFamily,
        bubbleIn: clearBubbleIn ? null : (bubbleIn ?? this.bubbleIn),
        bubbleOut: clearBubbleOut ? null : (bubbleOut ?? this.bubbleOut),
        wallpaper: clearWallpaper ? null : (wallpaper ?? this.wallpaper),
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'preset': preset.name,
        'accent': accent?.toARGB32(),
        'bubbleRadius': bubbleRadius,
        'fontScale': fontScale,
        'fontFamily': fontFamily,
        'bubbleIn': bubbleIn?.toARGB32(),
        'bubbleOut': bubbleOut?.toARGB32(),
        'wallpaper': wallpaper?.toARGB32(),
      };

  factory AppThemeSettings.fromJson(Map<String, dynamic> json) {
    Color? color(Object? raw) =>
        raw is int ? Color(raw) : null;
    return AppThemeSettings(
      mode: ThemeMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => ThemeMode.system,
      ),
      preset: AppThemePreset.fromName(json['preset'] as String?),
      accent: color(json['accent']),
      bubbleRadius: (json['bubbleRadius'] as num?)?.toDouble() ?? 16,
      fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
      fontFamily: json['fontFamily'] as String?,
      bubbleIn: color(json['bubbleIn']),
      bubbleOut: color(json['bubbleOut']),
      wallpaper: color(json['wallpaper']),
    );
  }
}

AppTheme buildAppTheme(AppThemeSettings settings, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  var palette = switch (settings.preset) {
    AppThemePreset.classic => dark ? AppPalette.night : AppPalette.day,
    AppThemePreset.blue => dark ? AppPalette.night : AppPalette.dayBlue,
    AppThemePreset.amoled => AppPalette.amoled,
  };
  if (settings.accent != null) {
    palette = palette.withAccent(settings.accent!);
  }
  if (settings.bubbleIn != null || settings.bubbleOut != null ||
      settings.wallpaper != null) {
    palette = palette.copyWith(
      bubbleIn: settings.bubbleIn,
      bubbleOut: settings.bubbleOut,
      chatWallpaper: settings.wallpaper,
    );
  }
  return AppTheme(
    brightness: brightness,
    palette: palette,
    typography: AppTypography.standard(
      baseSize: 13 * settings.fontScale,
      family: settings.fontFamily,
    ),
    metrics: AppMetrics.desktop.withBubbleRadius(settings.bubbleRadius),
    motion: AppMotion.standard,
  );
}

class AppThemeController extends StateNotifier<AppThemeSettings> {
  AppThemeController() : super(const AppThemeSettings()) {
    _load();
  }

  static const _key = 'app_theme_settings_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      state = AppThemeSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.toJson()));
  }

  Future<void> update(AppThemeSettings next) async {
    state = next;
    await _save();
  }

  Future<void> setMode(ThemeMode mode) => update(state.copyWith(mode: mode));

  Future<void> setPreset(AppThemePreset preset) =>
      update(state.copyWith(preset: preset));

  Future<void> setAccent(Color? accent) => update(
        accent == null
            ? state.copyWith(clearAccent: true)
            : state.copyWith(accent: accent),
      );

  Future<void> setBubbleRadius(double radius) => update(
        state.copyWith(
          bubbleRadius: radius.clamp(
            AppThemeSettings.minBubbleRadius,
            AppThemeSettings.maxBubbleRadius,
          ),
        ),
      );

  Future<void> setBubbleIn(Color? color) => update(
        color == null
            ? state.copyWith(clearBubbleIn: true)
            : state.copyWith(bubbleIn: color),
      );

  Future<void> setBubbleOut(Color? color) => update(
        color == null
            ? state.copyWith(clearBubbleOut: true)
            : state.copyWith(bubbleOut: color),
      );

  Future<void> setWallpaper(Color? color) => update(
        color == null
            ? state.copyWith(clearWallpaper: true)
            : state.copyWith(wallpaper: color),
      );

  Future<void> setFontScale(double scale) => update(
        state.copyWith(
          fontScale: scale.clamp(
            AppThemeSettings.minFontScale,
            AppThemeSettings.maxFontScale,
          ),
        ),
      );
}

final appThemeProvider =
    StateNotifierProvider<AppThemeController, AppThemeSettings>((ref) {
  return AppThemeController();
});

final appThemeLightProvider = Provider<AppTheme>((ref) {
  return buildAppTheme(ref.watch(appThemeProvider), Brightness.light);
});

final appThemeDarkProvider = Provider<AppTheme>((ref) {
  return buildAppTheme(ref.watch(appThemeProvider), Brightness.dark);
});
