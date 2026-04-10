import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vthumb;

import '../../../../localization/app_localizations.dart';
import '../../models/chat_message_models.dart';

class GalleryView extends StatefulWidget {
  final List<UiImage> images;
  final int initial;

  const GalleryView({required this.images, required this.initial});

  @override
  State<GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends State<GalleryView> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _galleryImage(UiImage img) {
    final isWebm = (img.filePath ?? '').toLowerCase().endsWith('.webm');
    if (isWebm && img.filePath != null) {
      return FutureBuilder<Uint8List?>(
        future: vthumb.VideoThumbnail.thumbnailData(
          video: img.filePath!,
          imageFormat: vthumb.ImageFormat.JPEG,
          maxWidth: 600,
          quality: 80,
        ),
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) {
            return const ColoredBox(color: Colors.black12);
          }
          return Image.memory(
            data,
            errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12),
          );
        },
      );
    }
    if (img.filePath != null) {
      return Image.file(
        File(img.filePath!),
        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12),
      );
    }
    return Image.memory(
      img.bytes!,
      errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        itemBuilder: (context, index) {
          final img = widget.images[index];
          return InteractiveViewer(
            child: Center(child: _galleryImage(img)),
          );
        },
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String filePath;

  const VideoPlayerScreen({required this.filePath});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _ready
            ? GestureDetector(
                onTap: () {
                  setState(() {
                    if (_controller.value.isPlaying) {
                      _controller.pause();
                    } else {
                      _controller.play();
                    }
                  });
                },
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
