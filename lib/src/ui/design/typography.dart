// Typography for TangleX.
//
// We rely on the platform default font (Roboto on Android, SF on iOS).
// No bundled font assets — keeps APK small and looks native.
//
// All TextStyles below are exposed through [TextTheme] so that widgets can
// use them as `Theme.of(context).textTheme.titleMedium` etc. Direct access
// is also available via the [AppText] helper.

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Centralised text styles.
///
/// Mapping to Material [TextTheme] roles is documented inline.
class AppText {
  const AppText._();

  // Headings
  static const TextStyle display = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  // Body
  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.35,
  );

  static const TextStyle bodyEmph = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.35,
  );

  // Secondary
  static const TextStyle caption = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.35,
  );

  static const TextStyle captionEmph = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.35,
  );

  // Small
  static const TextStyle meta = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.3,
  );

  static const TextStyle metaEmph = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  // Code
  static const TextStyle code = TextStyle(
    fontFamily: 'monospace',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  /// Build a Material [TextTheme] backed by these tokens.
  static TextTheme buildTextTheme() {
    return const TextTheme(
      // Material role → AppText role
      displayLarge: display,
      displayMedium: display,
      displaySmall: title,
      headlineLarge: title,
      headlineMedium: title,
      headlineSmall: titleSmall,
      titleLarge: title,
      titleMedium: titleSmall,
      titleSmall: captionEmph,
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: caption,
      labelLarge: captionEmph,
      labelMedium: meta,
      labelSmall: meta,
    );
  }
}
