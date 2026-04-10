import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vthumb;

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
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initial);
    _currentIndex = widget.initial;
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
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showImageActions(widget.images[_currentIndex]),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        onPageChanged: (idx) => setState(() => _currentIndex = idx),
        itemBuilder: (context, index) {
          final img = widget.images[index];
          return InteractiveViewer(
            child: Center(child: _galleryImage(img)),
          );
        },
      ),
    );
  }

  Future<void> _showImageActions(UiImage img) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.download, color: Colors.white),
                title: Text('Сохранить в галерею', style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _saveToGallery(img);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.white),
                title: Text('Поделиться', style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _shareImage(img);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.white),
                title: Text('Скопировать путь', style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _copyPath(img);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveToGallery(UiImage img) async {
    try {
      if (img.filePath != null && img.filePath!.isNotEmpty) {
        await ImageGallerySaver.saveFile(img.filePath!);
      } else if (img.bytes != null) {
        await ImageGallerySaver.saveImage(img.bytes!);
      } else {
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сохранено в галерею')),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сохранение недоступно. Перезапусти приложение.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить: $e')),
        );
      }
    }
  }

  Future<void> _shareImage(UiImage img) async {
    try {
      if (img.filePath != null && img.filePath!.isNotEmpty) {
        await Share.shareXFiles([XFile(img.filePath!)]);
        return;
      }
      if (img.bytes != null) {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/share_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await f.writeAsBytes(img.bytes!, flush: true);
        await Share.shareXFiles([XFile(f.path)]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось поделиться: $e')),
        );
      }
    }
  }

  Future<void> _copyPath(UiImage img) async {
    if (img.filePath == null || img.filePath!.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: img.filePath!));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Путь скопирован')),
      );
    }
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
