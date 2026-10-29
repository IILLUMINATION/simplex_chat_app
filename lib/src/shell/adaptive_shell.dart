import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../design/app_metrics.dart';
import '../design/app_theme.dart';

/// One-column phone, two-column tablet, three-column desktop — the same
/// breakpoints Telegram Desktop uses (640 / 932).
class AdaptiveShell extends StatefulWidget {
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
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

/// Tells the chat list column whether it is in Telegram's compact (avatar
/// rail) mode and how to expand back to a normal column.
class ChatListLayout extends InheritedWidget {
  const ChatListLayout({
    super.key,
    required this.compact,
    required this.expand,
    required super.child,
  });

  final bool compact;
  final VoidCallback expand;

  static ChatListLayout? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatListLayout>();

  @override
  bool updateShouldNotify(ChatListLayout oldWidget) =>
      compact != oldWidget.compact;
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  /// Telegram desktop keeps the dialogs width as a ratio of the body
  /// (5 / 14 by default) and lets the user drag the divider.
  static const _defaultListRatio = 5 / 14;

  /// Ratio 0 is Telegram's compact column: only avatars and badges.
  double? _listRatio;
  double? _detailsWidth;

  final _bodyKey = GlobalKey();

  /// `SessionController::dialogsSmallColumnWidth()`: row padding and photo.
  double _smallColumnWidth(AppMetrics metrics) =>
      metrics.listPadding.left + metrics.avatarSize + metrics.listPadding.left;

  double _listWidthFor(
    double width,
    AppMetrics metrics,
    double maxWidth,
  ) {
    final ratio = _listRatio;
    if (ratio == 0) {
      return math.min(_smallColumnWidth(metrics), maxWidth);
    }
    return (width * (ratio ?? _defaultListRatio)).clamp(
      metrics.leftColumnMin,
      maxWidth,
    );
  }

  /// Mirrors `MainWidget::ensureFirstColumnResizeAreaCreated`: the resize
  /// callback receives the divider's *global* position, not a per-event delta,
  /// so a fast pointer cannot outrun a stale layout width. Below half of the
  /// minimal column width the ratio collapses the list to the avatar rail;
  /// otherwise the ratio is that position divided by the window width.
  void _dragListAt(
    double globalX,
    AppMetrics metrics,
    double width,
  ) {
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final divider = box.globalToLocal(Offset(globalX, 0)).dx;
    final newWidth = divider - _ResizeHandle.width / 2;
    setState(() {
      _listRatio = newWidth < metrics.leftColumnMin / 2 ? 0 : newWidth / width;
    });
  }

  /// `MainWidget::ensureThirdColumnResizeAreaCreated` measures the details
  /// column from the window's right edge to the divider.
  void _dragDetailsAt(
    double globalX,
    AppMetrics metrics,
    double maxWidth,
    double width,
  ) {
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final divider = box.globalToLocal(Offset(globalX, 0)).dx;
    final newWidth = width - divider - _ResizeHandle.width / 2;
    setState(() {
      _detailsWidth = newWidth.clamp(metrics.thirdColumnMin, maxWidth);
    });
  }

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
              child: widget.chatSelected
                  ? KeyedSubtree(
                      key: const ValueKey('chat'),
                      child: widget.conversation,
                    )
                  : KeyedSubtree(
                      key: const ValueKey('list'),
                      child: widget.chatList,
                    ),
            ),
          );
        }

        final showDetails =
            widget.details != null &&
            widget.detailsOpen &&
            width >= metrics.threeColumnBreakpoint;
        final detailsMax = math.min(
          metrics.thirdColumnMax,
          width * 0.4,
        );
        final detailsWidth = showDetails
            ? (_detailsWidth ?? metrics.thirdColumnMin).clamp(
                metrics.thirdColumnMin,
                detailsMax,
              )
            : 0.0;
        final reserved = showDetails
            ? detailsWidth + _ResizeHandle.width * 2
            : _ResizeHandle.width;
        final listMax = math.max(
          metrics.leftColumnMin,
          width - metrics.chatColumnMin - reserved,
        );
        final listWidth = _listWidthFor(width, metrics, listMax);
        final compactList = listWidth < metrics.leftColumnMin / 2;

        return AppThemeScope(
          theme: scoped,
          child: Row(
            key: _bodyKey,
            children: [
              SizedBox(
                key: const ValueKey('chat-list-column'),
                width: listWidth,
                child: ChatListLayout(
                  compact: compactList,
                  expand: () =>
                      setState(() => _listRatio = _defaultListRatio),
                  child: widget.chatList,
                ),
              ),
              _ResizeHandle(
                key: const ValueKey('chat-list-resize'),
                onDragTo: (globalX) => _dragListAt(globalX, metrics, width),
              ),
              Expanded(
                child: widget.chatSelected
                    ? widget.conversation
                    : widget.emptyConversation,
              ),
              if (showDetails) ...[
                _ResizeHandle(
                  key: const ValueKey('details-resize'),
                  onDragTo: (globalX) =>
                      _dragDetailsAt(globalX, metrics, detailsMax, width),
                ),
                SizedBox(
                  key: const ValueKey('details-column'),
                  width: detailsWidth,
                  child: widget.details,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Thin splitter with a wide hit area: the cursor turns into ↔ on hover and
/// dragging moves it, exactly like Telegram's `Ui::ResizeArea`.
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({
    super.key,
    required this.onDragTo,
  });

  static const width = 5.0;

  /// Receives the divider's global x for the current pointer position.
  final ValueChanged<double> onDragTo;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  /// Keeps the divider from jumping when the grab lands off the 1px line.
  double _grabOffset = 0;

  void _start(DragStartDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    _grabOffset =
        details.globalPosition.dx -
        box.localToGlobal(Offset(box.size.width / 2, 0)).dx;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: _start,
        onHorizontalDragUpdate: (details) =>
            widget.onDragTo(details.globalPosition.dx - _grabOffset),
        child: SizedBox(
          width: _ResizeHandle.width,
          child: Center(
            child: Container(width: 1, color: theme.palette.divider),
          ),
        ),
      ),
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
