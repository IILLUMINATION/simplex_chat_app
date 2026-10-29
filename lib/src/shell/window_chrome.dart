import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/app_theme.dart';

/// Edges accepted by `tanglex/window#startResize`; the order matches the
/// `GdkWindowEdge` table in `linux/runner/my_application.cc`.
enum WindowResizeEdge {
  topLeft,
  top,
  topRight,
  left,
  right,
  bottomLeft,
  bottom,
  bottomRight,
}

/// Desktop window controls backed by the GTK runner.
///
/// Telegram Desktop draws its own 24px title strip instead of relying on the
/// window manager; [WindowChrome] mirrors that on Linux and falls back to the
/// bare child everywhere else.
class WindowChrome extends StatefulWidget {
  const WindowChrome({super.key, required this.child});

  final Widget child;

  /// Phone and web builds keep the platform's own window.
  static bool get supported => !kIsWeb && Platform.isLinux;

  @override
  State<WindowChrome> createState() => _WindowChromeState();
}

class WindowChromeController {
  WindowChromeController._();

  static final WindowChromeController instance = WindowChromeController._();

  static const _channel = MethodChannel('tanglex/window');

  /// Mirror of the native window state, updated from `window-state-event`.
  final ValueNotifier<bool> maximized = ValueNotifier<bool>(false);

  Future<void> minimize() => _invoke('minimize');

  Future<void> toggleMaximize() => _invoke('toggleMaximize');

  Future<void> close() => _invoke('close');

  Future<void> startDrag() => _invoke('startDrag');

  Future<void> startResize(WindowResizeEdge edge) =>
      _invoke('startResize', <String, Object?>{'edge': edge.index});

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Widget tests and non-Linux hosts have no native window.
    } on PlatformException {
      // The window is closing or the compositor refused the request.
    }
  }

  Future<bool> readMaximized() async {
    try {
      return await _channel.invokeMethod<bool>('isMaximized') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> syncState() async {
    maximized.value = await readMaximized();
  }

  static void attachStateListener() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'state') {
        final args = call.arguments;
        if (args is Map && args['maximized'] is bool) {
          instance.maximized.value = args['maximized'] as bool;
        }
      }
      return null;
    });
  }

  static void detachStateListener() {
    _channel.setMethodCallHandler(null);
  }
}

class _WindowChromeState extends State<WindowChrome> {
  @override
  void initState() {
    super.initState();
    if (!WindowChrome.supported) return;
    WindowChromeController.attachStateListener();
    WindowChromeController.instance.syncState();
  }

  @override
  void dispose() {
    if (WindowChrome.supported) {
      WindowChromeController.detachStateListener();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!WindowChrome.supported) return widget.child;
    return Stack(
      children: [
        Column(
          children: [
            const _TitleStrip(),
            Expanded(child: widget.child),
          ],
        ),
        Positioned.fill(
          child: ValueListenableBuilder<bool>(
            valueListenable: WindowChromeController.instance.maximized,
            builder: (context, maximized, _) => IgnorePointer(
              ignoring: maximized,
              child: const _ResizeHandles(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Height and control geometry measured from Telegram Desktop's Linux frame.
const double _titleStripHeight = 24;
const double _titleButtonWidth = 36;

class _TitleStrip extends StatelessWidget {
  const _TitleStrip();

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme.palette;
    final controller = WindowChromeController.instance;
    return SizedBox(
      height: _titleStripHeight,
      child: ColoredBox(
        color: palette.searchBg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: controller.toggleMaximize,
              onPanStart: (_) => controller.startDrag(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TitleButton(
                    glyph: _TitleGlyph.minimize,
                    tooltip: 'Minimize',
                    onPressed: controller.minimize,
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: controller.maximized,
                    builder: (context, maximized, _) => _TitleButton(
                      glyph: maximized
                          ? _TitleGlyph.restore
                          : _TitleGlyph.maximize,
                      tooltip: maximized ? 'Restore' : 'Maximize',
                      onPressed: controller.toggleMaximize,
                    ),
                  ),
                  _TitleButton(
                    glyph: _TitleGlyph.close,
                    tooltip: 'Close',
                    onPressed: controller.close,
                    destructive: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleButton extends StatefulWidget {
  const _TitleButton({
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    this.destructive = false,
  });

  final _TitleGlyph glyph;
  final String tooltip;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  State<_TitleButton> createState() => _TitleButtonState();
}

class _TitleButtonState extends State<_TitleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme.palette;
    final hoverColor = widget.destructive
        ? palette.error
        : palette.text.withValues(alpha: 0.06);
    final iconColor = (_hovered && widget.destructive)
        ? palette.onAccent
        : palette.icon;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: _titleButtonWidth,
            height: _titleStripHeight,
            color: _hovered ? hoverColor : const Color(0x00000000),
            child: Center(
              child: CustomPaint(
                size: const Size(12, 12),
                painter: _TitleGlyphPainter(
                  widget.glyph,
                  iconColor,
                  _hovered && widget.destructive
                      ? hoverColor
                      : _hovered
                      ? Color.alphaBlend(hoverColor, palette.searchBg)
                      : palette.searchBg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _TitleGlyph { minimize, maximize, restore, close }

class _TitleGlyphPainter extends CustomPainter {
  const _TitleGlyphPainter(this.glyph, this.color, this.backdrop);

  final _TitleGlyph glyph;
  final Color color;

  /// Painted between the two sheets of the restore glyph so the back one
  /// reads as an L, the way Telegram's icon font draws it.
  final Color backdrop;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square;
    final left = (size.width - 10) / 2;
    final top = (size.height - 10) / 2;
    switch (glyph) {
      case _TitleGlyph.minimize:
        // Telegram's glyph sits below the optical centre of its em box.
        final y = top + 8.3;
        canvas.drawLine(Offset(left + 0.3, y), Offset(left + 9.9, y), paint);
      case _TitleGlyph.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left + 0.5, top + 0.5, 9, 9),
            const Radius.circular(1.5),
          ),
          paint,
        );
      case _TitleGlyph.restore:
        final front = RRect.fromRectAndRadius(
          Rect.fromLTWH(left + 0.4, top + 3.1, 8, 7.2),
          const Radius.circular(1.3),
        );
        final back = RRect.fromRectAndRadius(
          Rect.fromLTWH(left + 2.8, top + 0.7, 7.2, 6.4),
          const Radius.circular(1.3),
        );
        canvas.drawRRect(back, paint);
        canvas.drawRRect(
          front.inflate(1.2),
          Paint()..color = backdrop,
        );
        canvas.drawRRect(front, paint);
      case _TitleGlyph.close:
        canvas.drawLine(
          Offset(left + 1, top + 1),
          Offset(left + 9, top + 9),
          paint,
        );
        canvas.drawLine(
          Offset(left + 9, top + 1),
          Offset(left + 1, top + 9),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_TitleGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.backdrop != backdrop;
}

/// Frameless windows have no manager-provided grips, so the app carries them:
/// a resize band along every edge.
class _ResizeHandles extends StatelessWidget {
  const _ResizeHandles();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _handle(
          left: 0,
          top: 0,
          width: 12,
          height: 12,
          cursor: SystemMouseCursors.resizeUpLeft,
          edge: WindowResizeEdge.topLeft,
        ),
        _handle(
          right: 0,
          top: 0,
          width: 12,
          height: 12,
          cursor: SystemMouseCursors.resizeUpRight,
          edge: WindowResizeEdge.topRight,
        ),
        _handle(
          left: 0,
          bottom: 0,
          width: 12,
          height: 12,
          cursor: SystemMouseCursors.resizeDownLeft,
          edge: WindowResizeEdge.bottomLeft,
        ),
        _handle(
          right: 0,
          bottom: 0,
          width: 12,
          height: 12,
          cursor: SystemMouseCursors.resizeDownRight,
          edge: WindowResizeEdge.bottomRight,
        ),
        _handle(
          left: 12,
          right: 12,
          top: 0,
          height: 4,
          cursor: SystemMouseCursors.resizeUp,
          edge: WindowResizeEdge.top,
        ),
        _handle(
          left: 12,
          right: 12,
          bottom: 0,
          height: 4,
          cursor: SystemMouseCursors.resizeDown,
          edge: WindowResizeEdge.bottom,
        ),
        _handle(
          left: 0,
          top: 12,
          bottom: 12,
          width: 4,
          cursor: SystemMouseCursors.resizeLeft,
          edge: WindowResizeEdge.left,
        ),
        _handle(
          right: 0,
          top: 12,
          bottom: 12,
          width: 4,
          cursor: SystemMouseCursors.resizeRight,
          edge: WindowResizeEdge.right,
        ),
      ],
    );
  }

  Widget _handle({
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? width,
    double? height,
    required MouseCursor cursor,
    required WindowResizeEdge edge,
  }) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: cursor,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) =>
              WindowChromeController.instance.startResize(edge),
        ),
      ),
    );
  }
}
