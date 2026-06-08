import 'package:flutter/material.dart';

import '../tokens.dart';

/// A subtle shimmering rectangle used as a list-loading placeholder.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = AppRadius.rs,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = (_c.value - 0.5).abs() * 2; // 0..1..0
        final color = Color.lerp(
          AppColors.surface2,
          AppColors.surface3,
          t,
        )!;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// A skeleton tile for the chats list.
class AppChatTileSkeleton extends StatelessWidget {
  const AppChatTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      child: Row(
        children: [
          const AppSkeleton(
            width: AppAvatarSize.large,
            height: AppAvatarSize.large,
            radius: AppRadius.rfull,
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeleton(
                  height: 14,
                  width: 160,
                ),
                SizedBox(height: AppSpacing.s2),
                AppSkeleton(height: 12, width: 220),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
