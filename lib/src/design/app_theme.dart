import 'package:flutter/material.dart';

import 'app_metrics.dart';
import 'app_palette.dart';
import 'app_typography.dart';

/// The single source of every visual value in the app.
///
/// Widgets read it through [AppThemeScope.of] and never hardcode colors,
/// radii or durations, so a user theme can restyle the whole client.
@immutable
class AppTheme {
  const AppTheme({
    required this.brightness,
    required this.palette,
    required this.typography,
    required this.metrics,
    required this.motion,
  });

  final Brightness brightness;
  final AppPalette palette;
  final AppTypography typography;
  final AppMetrics metrics;
  final AppMotion motion;

  bool get isDark => brightness == Brightness.dark;

  AppTheme copyWith({
    Brightness? brightness,
    AppPalette? palette,
    AppTypography? typography,
    AppMetrics? metrics,
    AppMotion? motion,
  }) =>
      AppTheme(
        brightness: brightness ?? this.brightness,
        palette: palette ?? this.palette,
        typography: typography ?? this.typography,
        metrics: metrics ?? this.metrics,
        motion: motion ?? this.motion,
      );

  ThemeData toMaterial() {
    final p = palette;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      primaryContainer: p.accentOver,
      onPrimaryContainer: p.onAccent,
      secondary: p.link,
      onSecondary: p.onAccent,
      secondaryContainer: p.windowBgOver,
      onSecondaryContainer: p.text,
      error: p.error,
      onError: p.onAccent,
      surface: p.windowBg,
      onSurface: p.text,
      surfaceContainerHighest: p.windowBgOver,
      onSurfaceVariant: p.textSecondary,
      outline: p.divider,
      outlineVariant: p.divider,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: p.text,
      onInverseSurface: p.windowBg,
      inversePrimary: p.accentRipple,
    );

    final t = typography;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.windowBg,
      canvasColor: p.windowBg,
      dividerColor: p.divider,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: p.windowBgOver,
      fontFamily: t.message.fontFamily,
      textTheme: TextTheme(
        titleLarge: t.chatTitle.copyWith(color: p.text),
        titleMedium: t.listName.copyWith(color: p.text),
        titleSmall: t.sectionHeader.copyWith(color: p.textSecondary),
        bodyLarge: t.message.copyWith(color: p.text),
        bodyMedium: t.message.copyWith(color: p.text),
        bodySmall: t.messageMeta.copyWith(color: p.textSecondary),
        labelLarge: t.button.copyWith(color: p.onAccent),
        labelMedium: t.listTime.copyWith(color: p.textSecondary),
        labelSmall: t.listTime.copyWith(color: p.textSecondary),
      ),
      iconTheme: IconThemeData(color: p.icon, size: metrics.iconSize),
      dividerTheme: DividerThemeData(
        color: p.divider,
        thickness: 1,
        space: 1,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(4),
        radius: const Radius.circular(2),
        thumbColor: WidgetStatePropertyAll(p.icon.withValues(alpha: 0.4)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? p.windowBgOver : const Color(0xE6222222),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: typography.messageMeta.copyWith(color: p.onAccent),
        waitDuration: const Duration(milliseconds: 400),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.accent.withValues(alpha: 0.25),
        selectionHandleColor: p.accent,
      ),
    );
  }

  static AppTheme lerp(AppTheme a, AppTheme b, double t) => AppTheme(
        brightness: t < 0.5 ? a.brightness : b.brightness,
        palette: AppPalette.lerp(a.palette, b.palette, t),
        typography: AppTypography.lerp(a.typography, b.typography, t),
        metrics: AppMetrics.lerp(a.metrics, b.metrics, t),
        motion: t < 0.5 ? a.motion : b.motion,
      );
}

class AppThemeScope extends InheritedWidget {
  const AppThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

  final AppTheme theme;

  static AppTheme of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'AppThemeScope is missing above this widget');
    return scope!.theme;
  }

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) => theme != oldWidget.theme;
}

extension AppThemeX on BuildContext {
  AppTheme get appTheme => AppThemeScope.of(this);

  AppPalette get palette => appTheme.palette;

  AppTypography get type => appTheme.typography;

  AppMetrics get metrics => appTheme.metrics;

  AppMotion get motion => appTheme.motion;
}
