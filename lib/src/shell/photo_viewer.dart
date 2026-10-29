import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// Telegram's media viewer: a black full-screen pager over the chat, pinch or
/// double-click to zoom, wheel/arrow keys and on-screen chevrons to walk an
/// album (`viewer/viewer_widget.cpp`, `Viewer::setupShortcuts`).
Future<void> showPhotoViewer(
  BuildContext context, {
  required List<AlbumTile> tiles,
  int initialIndex = 0,
}) {
  if (tiles.isEmpty) return Future<void>.value();
  final index = initialIndex.clamp(0, tiles.length - 1);
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, _, _) =>
          PhotoViewer(tiles: tiles, initialIndex: index),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.tiles,
    this.initialIndex = 0,
  });

  final List<AlbumTile> tiles;
  final int initialIndex;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pages;
  late int _index;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.tiles.length) return;
    _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (_zoomed) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final multiple = widget.tiles.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: Listener(
                  onPointerSignal: (event) {
                    if (!multiple || _zoomed) return;
                    if (event is! PointerScrollEvent) return;
                    final dy = event.scrollDelta.dy;
                    if (dy == 0) return;
                    _go(dy > 0 ? 1 : -1);
                  },
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: widget.tiles.length,
                    onPageChanged: (index) => setState(() => _index = index),
                    itemBuilder: (context, index) => _ViewerPage(
                      key: ValueKey('viewer-page-$index'),
                      tile: widget.tiles[index],
                      onZoomChanged: (zoomed) {
                        if (zoomed != _zoomed) {
                          setState(() => _zoomed = zoomed);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (multiple)
              Positioned(
                left: 16,
                top: 14,
                child: _ViewerChip(
                  child: Text(
                    '${_index + 1} / ${widget.tiles.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 12,
              top: 10,
              child: _ViewerButton(
                icon: Icons.close,
                tooltip: 'Close',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            if (multiple && !_zoomed) ...[
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _ViewerButton(
                    icon: Icons.chevron_left,
                    tooltip: 'Previous',
                    onTap: _index > 0 ? () => _go(-1) : null,
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _ViewerButton(
                    icon: Icons.chevron_right,
                    tooltip: 'Next',
                    onTap: _index < widget.tiles.length - 1
                        ? () => _go(1)
                        : null,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ViewerPage extends StatefulWidget {
  const _ViewerPage({super.key, required this.tile, this.onZoomChanged});

  final AlbumTile tile;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  final _zoom = TransformationController();
  bool _zoomed = false;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _setZoomed(bool zoomed) {
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
  }

  void _toggleZoom() {
    if (_zoom.value.getMaxScaleOnAxis() > 1.01) {
      _zoom.value = Matrix4.identity();
    } else {
      _zoom.value = Matrix4.diagonal3Values(2.5, 2.5, 1);
    }
    _setZoomed(_zoom.value.getMaxScaleOnAxis() > 1.01);
  }

  Widget _image() {
    final tile = widget.tile;
    final path = tile.path;
    if (path != null && !tile.isVideo && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final bytes = widget.tile.bytes;
    if (bytes == null) {
      return const Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: Colors.white54,
        ),
      );
    }
    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: Colors.white54,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _zoom,
      minScale: 1,
      maxScale: 6,
      panEnabled: _zoomed,
      onInteractionUpdate: (_) => _setZoomed(
        _zoom.value.getMaxScaleOnAxis() > 1.01,
      ),
      child: Center(
        // A tap on the photo itself is absorbed by the viewer; only the black
        // background behind it closes the route. Double tap toggles the zoom.
        child: GestureDetector(
          onTap: () {},
          onDoubleTap: _toggleZoom,
          child: _image(),
        ),
      ),
    );
  }
}

class _ViewerButton extends StatelessWidget {
  const _ViewerButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 26,
              color: enabled ? Colors.white : Colors.white30,
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerChip extends StatelessWidget {
  const _ViewerChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}
