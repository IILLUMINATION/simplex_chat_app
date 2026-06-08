import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';

/// Centered "nothing here yet" empty state with icon, title, and hint.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.surface2,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: AppColors.textSecondary,
                size: 36,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.titleSmall,
            ),
            if (hint != null) ...[
              const SizedBox(height: AppSpacing.s2),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: AppText.caption,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.s5),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
