// Bottom-sheet helpers.

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';

/// Drag handle shown at the top of every modal sheet.
class AppSheetHandle extends StatelessWidget {
  const AppSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      child: Center(
        child: Container(
          width: 36,
          height: 3,
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(AppRadius.rfull),
          ),
        ),
      ),
    );
  }
}

/// Standard wrapper for modal sheet content.
///
/// Provides: drag-handle, optional title, safe-area bottom padding.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.child,
    this.title,
    this.trailing,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppSheetHandle(),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s5,
                AppSpacing.s1,
                AppSpacing.s3,
                AppSpacing.s3,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title!, style: AppText.titleSmall),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// Show a modal bottom sheet with the design system's defaults.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: AppColors.surface1,
    barrierColor: AppColors.scrim,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
    builder: builder,
  );
}
