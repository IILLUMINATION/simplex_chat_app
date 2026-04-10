import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vthumb;

import '../../models/chat_message_models.dart';
import '../../utils/chat_message_parser.dart';

class MediaGrid extends StatelessWidget {
  final List<UiImage> images;
  final bool fromMe;
  final void Function(int index) onOpen;
  final void Function(int index) onDownload;

  const MediaGrid({
    required this.images,
    required this.fromMe,
    required this.onOpen,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final count = images.length.clamp(1, 4);
    final cols = count == 1 ? 1 : (count == 2 ? 2 : 2);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        final img = images[index];
        Widget child = img.isSticker
            ? StickerView(image: img)
            : img.isVideo && img.isCircle
                ? VideoCircle(image: img)
                : img.isVideo
                    ? VideoThumbRect(image: img)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildImage(img),
                      );

        final isIncoming = !fromMe;
        final needsDownload = isIncoming &&
            !img.hasFullImage &&
            img.fileId != null &&
            img.fileStatusType == 'rcvInvitation';
        final isDownloading = isIncoming &&
            (img.fileStatusType == 'rcvTransfer' || img.fileStatusType == 'rcvAccepted');
        final isSending = fromMe && img.fileStatusType == 'sndTransfer';
        final showProgress = (img.fileStatusType == 'rcvTransfer' ||
                img.fileStatusType == 'rcvAccepted' ||
                img.fileStatusType == 'sndTransfer') &&
            (img.transferTotal != null && img.transferTotal! > 0) &&
            img.transferProgress != null;
        final progress = showProgress ? (img.transferProgress! / img.transferTotal!) : null;
        if (needsDownload) {
          child = Stack(
            fit: StackFit.expand,
            children: [
              child,
              Container(color: Colors.black26),
              Center(
                child: GestureDetector(
                  onTap: () => onDownload(index),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.download, color: Colors.white, size: 26),
                  ),
                ),
              ),
            ],
          );
        } else if (isDownloading) {
          child = Stack(
            fit: StackFit.expand,
            children: [
              child,
              Container(color: Colors.black26),
              Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: showProgress
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: progress,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                ),
              ),
            ],
          );
        } else if (isSending || showProgress) {
          child = Stack(
            fit: StackFit.expand,
            children: [
              child,
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: progress,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return GestureDetector(
          onTap: () => onOpen(index),
          child: child,
        );
      },
    );
  }

  Widget _buildImage(UiImage img) {
    if (img.filePath != null) {
      return Image.file(
        File(img.filePath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12),
      );
    }
    if (img.bytes != null) {
      return Image.memory(
        img.bytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12),
      );
    }
    return const SizedBox.shrink();
  }
}

class VideoThumbRect extends StatelessWidget {
  final UiImage image;

  const VideoThumbRect({required this.image});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image.bytes != null)
            Image.memory(image.bytes!, fit: BoxFit.cover)
          else if (image.filePath != null)
            Image.file(File(image.filePath!), fit: BoxFit.cover)
          else
            const ColoredBox(color: Colors.black38),
          Container(color: Colors.black26),
          Center(
            child: Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 26),
            ),
          ),
          if (image.durationSec != null)
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  formatDuration(image.durationSec!),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class VideoCircle extends StatefulWidget {
  final UiImage image;

  const VideoCircle({required this.image});

  @override
  State<VideoCircle> createState() => _VideoCircleState();
}

class _VideoCircleState extends State<VideoCircle> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.image.filePath != null) {
      _controller = VideoPlayerController.file(File(widget.image.filePath!))
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
        });
    }
  }

  @override
  void didUpdateWidget(covariant VideoCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.filePath != widget.image.filePath) {
      _controller?.dispose();
      _controller = null;
      if (widget.image.filePath != null) {
        _controller = VideoPlayerController.file(File(widget.image.filePath!))
          ..initialize().then((_) {
            if (!mounted) return;
            setState(() {});
          });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggle() {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (!ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final img = widget.image;
    final ctrl = _controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return AnimatedBuilder(
          animation: ctrl ?? const AlwaysStoppedAnimation(0),
          builder: (context, _) {
            final isPlaying = ctrl?.value.isPlaying ?? false;
            final progress = (ctrl != null &&
                    ctrl.value.isInitialized &&
                    ctrl.value.duration.inMilliseconds > 0)
                ? (ctrl.value.position.inMilliseconds /
                    ctrl.value.duration.inMilliseconds)
                : 0.0;
            return GestureDetector(
              onTap: _toggle,
              onPanStart: (d) => _seekByOffset(d.localPosition, size),
              onPanUpdate: (d) => _seekByOffset(d.localPosition, size),
              child: AnimatedScale(
                scale: isPlaying ? 1.08 : 0.92,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipOval(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (ctrl != null && ctrl.value.isInitialized)
                            _videoBox(ctrl, size.shortestSide)
                          else
                            _previewBox(img, size.shortestSide),
                          Container(color: Colors.black26),
                        ],
                      ),
                    ),
                    CustomPaint(
                      size: size,
                      painter: RingProgressPainter(
                        progress: progress,
                        color: Colors.white,
                        stroke: 7,
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    if (img.durationSec != null && !isPlaying)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            formatDuration(img.durationSec!),
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _videoBox(VideoPlayerController ctrl, double side) {
    final ratio = ctrl.value.aspectRatio == 0 ? 1.0 : ctrl.value.aspectRatio;
    final width = ratio >= 1 ? side * ratio : side;
    final height = ratio >= 1 ? side : side / ratio;
    return SizedBox.square(
      dimension: side,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: width,
          height: height,
          child: VideoPlayer(ctrl),
        ),
      ),
    );
  }

  Widget _previewBox(UiImage img, double side) {
    return SizedBox.square(
      dimension: side,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: side,
          height: side,
          child: img.bytes != null
              ? Image.memory(img.bytes!, fit: BoxFit.cover)
              : const ColoredBox(color: Colors.black38),
        ),
      ),
    );
  }

  void _seekByOffset(Offset pos, Size size) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final center = size.center(Offset.zero);
    final dx = pos.dx - center.dx;
    final dy = pos.dy - center.dy;
    final angle = (math.atan2(dy, dx) + math.pi / 2) % (2 * math.pi);
    final progress = (angle / (2 * math.pi)).clamp(0.0, 1.0);
    final targetMs = (ctrl.value.duration.inMilliseconds * progress).toInt();
    ctrl.seekTo(Duration(milliseconds: targetMs));
    setState(() {});
  }
}

class StickerView extends StatelessWidget {
  final UiImage image;

  const StickerView({required this.image});

  @override
  Widget build(BuildContext context) {
    const size = 140.0;
    Widget child;
    if (image.isWebm && image.filePath != null) {
      child = StickerWebm(filePath: image.filePath!);
    } else if (image.filePath != null) {
      child = Image.file(
        File(image.filePath!),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } else if (image.bytes != null) {
      child = Image.memory(
        image.bytes!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } else {
      child = const SizedBox.shrink();
    }
    return SizedBox(
      width: size,
      height: size,
      child: child,
    );
  }
}

class StickerThumb extends StatelessWidget {
  final String filePath;

  const StickerThumb({required this.filePath});

  @override
  Widget build(BuildContext context) {
    if (filePath.toLowerCase().endsWith('.webm')) {
      return FutureBuilder<Uint8List?>(
        future: vthumb.VideoThumbnail.thumbnailData(
          video: filePath,
          imageFormat: vthumb.ImageFormat.JPEG,
          maxWidth: 200,
          quality: 60,
        ),
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) {
            return const ColoredBox(color: Colors.black12);
          }
          return Image.memory(
            data,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12),
          );
        },
      );
    }
    return Image.file(
      File(filePath),
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12),
    );
  }
}

class StickerWebm extends StatelessWidget {
  final String filePath;

  const StickerWebm({required this.filePath});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: vthumb.VideoThumbnail.thumbnailData(
        video: filePath,
        imageFormat: vthumb.ImageFormat.JPEG,
        maxWidth: 280,
        quality: 75,
      ),
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) {
          return const ColoredBox(color: Colors.black12);
        }
        return Image.memory(
          data,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12),
        );
      },
    );
  }
}

class RingProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double stroke;

  RingProgressPainter({
    required this.progress,
    required this.color,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - stroke) / 2;
    final base = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final active = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, base);
    final sweep = (progress.clamp(0.0, 1.0)) * 6.283185307179586;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      sweep,
      false,
      active,
    );
  }

  @override
  bool shouldRepaint(covariant RingProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
