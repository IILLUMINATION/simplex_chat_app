// Helpers for AlertDialog using design tokens.

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';

/// Show a styled confirmation dialog.
/// Returns true if confirmed, false/null otherwise.
Future<bool?> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface2,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brm),
      title: Text(title, style: AppText.title),
      content: Text(message, style: AppText.body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor:
                destructive ? AppColors.error : AppColors.accent,
            foregroundColor: AppColors.textOnAccent,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
