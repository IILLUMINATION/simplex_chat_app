// Centralised SnackBar helpers using design tokens.

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';

enum AppSnackKind { info, error, success }

void showAppSnack(
  BuildContext context, {
  required String message,
  AppSnackKind kind = AppSnackKind.info,
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final Color bg;
  final IconData icon;
  switch (kind) {
    case AppSnackKind.error:
      bg = AppColors.error;
      icon = Icons.error_outline_rounded;
      break;
    case AppSnackKind.success:
      bg = AppColors.success;
      icon = Icons.check_circle_outline_rounded;
      break;
    case AppSnackKind.info:
      bg = AppColors.surface2;
      icon = Icons.info_outline_rounded;
      break;
  }
  final fg = kind == AppSnackKind.info
      ? AppColors.textPrimary
      : AppColors.textOnAccent;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      duration: duration,
      action: action,
      margin: const EdgeInsets.all(AppSpacing.s4),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brm),
      content: Row(
        children: [
          Icon(icon, color: fg, size: AppIconSize.small),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(message, style: AppText.body.copyWith(color: fg)),
          ),
        ],
      ),
    ),
  );
}
