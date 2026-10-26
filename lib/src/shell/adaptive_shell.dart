import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/app_metrics.dart';
import '../design/app_theme.dart';

/// One-column phone, two-column tablet, three-column desktop — the same
/// breakpoints Telegram Desktop uses (640 / 932).
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({
    super.key,
    required this.chatList,
    required this.conversation,
    required this.emptyConversation,
    this.details,
    this.chatSelected = false,
    this.detailsOpen = false,
  });

  final Widget chatList;
  final Widget conversation;
  final Widget emptyConversation;
  final Widget? details;
  final bool chatSelected;
  final bool detailsOpen;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final radius = theme.metrics.bubbleRadius;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final metrics = AppMetrics.forWidth(width).withBubbleRadius(radius);
        final scoped = theme.copyWith(
          metrics: metrics,
          typography: metrics.compact ? theme.typography.forPhone : null,
        );

        if (width < metrics.twoColumnBreakpoint) {
          return AppThemeScope(
            theme: scoped,
            child: AnimatedSwitcher(
              duration: theme.motion.wrap,
              switchInCurve: AppMotion.ease,
              switchOutCurve: AppMotion.ease,
              child: chatSelected
                  ? KeyedSubtree(
                      key: const ValueKey('chat'),
                      child: conversation,
                    )
                  : KeyedSubtree(key: const ValueKey('list'), child: chatList),
            ),
          );
        }

        final showDetails =
            details != null &&
            detailsOpen &&
            width >= metrics.threeColumnBreakpoint;
        final thirdWidth = showDetails ? metrics.thirdColumnMin : 0.0;
        final maxListWidth = math.max(
          metrics.leftColumnMin,
          width - metrics.chatColumnMin - thirdWidth,
        );
        final listWidth = math.min(
          metrics.leftColumnMax,
          math.max(metrics.leftColumnMin, width * 0.32),
        );
        final clampedList = math.min(listWidth, maxListWidth);

        return AppThemeScope(
          theme: scoped,
          child: Row(
            children: [
              AnimatedContainer(
                duration: theme.motion.universal,
                curve: AppMotion.ease,
                width: clampedList,
                child: chatList,
              ),
              Container(width: 1, color: theme.palette.divider),
              Expanded(child: chatSelected ? conversation : emptyConversation),
              if (showDetails) ...[
                Container(width: 1, color: theme.palette.divider),
                SizedBox(width: metrics.thirdColumnMin, child: details),
              ],
            ],
          ),
        );
      },
    );
  }
}

class EmptyConversation extends StatelessWidget {
  const EmptyConversation({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return ColoredBox(
      color: p.windowBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: p.icon),
            const SizedBox(height: 12),
            Text(
              'Select a chat to start messaging',
              style: theme.typography.listPreview.copyWith(
                color: p.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
