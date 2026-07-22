// TangleX — Material 3 theme.
//
// Single source of truth for the app's ColorScheme and ThemeData. Per
// HANDOFF.md § 9, all colors come from `ColorScheme.fromSeed`; widgets MUST
// reference `Theme.of(context).colorScheme.<role>` and never hardcode hex.
//
// The seed `#2AABEE` (Telegram-blue) is a placeholder until the user provides
// a `DESIGN.md`. Replace only the seed below to re-skin the whole app.

import 'package:flutter/material.dart';
import '../core/theme/tx_theme.dart';

/// Placeholder seed color until DESIGN.md ships.
const Color kBrandSeed = Color(0xFF2AABEE);

/// Builds the dark Material 3 theme used by the whole app.
ThemeData buildDarkTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: kBrandSeed,
    brightness: Brightness.dark,
  );
  return _themeFromScheme(colorScheme);
}

/// Builds the light Material 3 theme (currently unused — app is dark-only,
/// see HANDOFF.md § 9 — but defined so we can flip a switch later).
ThemeData buildLightTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: kBrandSeed,
    brightness: Brightness.light,
  );
  return _themeFromScheme(colorScheme);
}

ThemeData _themeFromScheme(ColorScheme colorScheme) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    extensions: [
      TxChatTheme.amoledDark(),
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: colorScheme.surfaceTint,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 2,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surfaceContainer,
      indicatorColor: colorScheme.secondaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          color: colorScheme.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.onSurfaceVariant,
      textColor: colorScheme.onSurface,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
  );
}
