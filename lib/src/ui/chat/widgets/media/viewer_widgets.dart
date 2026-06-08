import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../../localization/app_localizations.dart';
import '../../../design/design.dart';
import '../../models/chat_message_models.dart';
import 'media_widgets.dart' show thumbCache, generateVideoThumb;

class GalleryView extends StatefulWidget {
  const GalleryView({super.key, required this.images, required this.initial});

  final List<UiImage> images;
  final int initial;

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
      final path = img.filePath!;
      final cached = thumbCache[path];
      if (cached != null) {
        return Image.memory(
          cached,
          errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12),
        );
      }
      final future = generateVideoThumb(path, 600, 80);
      return FutureBuilder<Uint8List?>(
        future: future,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) {
            return const ColoredBox(color: Colors.black12);
          }
          return Image.memory(
            data,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Colors.black12),
          );
        },
      );
    }
    if (img.filePath != null) {
      return Image.file(
        File(img.filePath!),
        errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12),
      );
    }
    return Image.memory(
      img.bytes!,
      errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12),
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
            icon: const Icon(Icons.more_vert_rounded),
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
          return InteractiveViewer(child: Center(child: _galleryImage(img)));
        },
      ),
    );
  }

  Future<void> _showImageActions(UiImage img) async {
    final loc = AppLocalizations.of(context);
    await showAppSheet<void>(
      context: context,
      builder: (ctx) => AppSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: Text(loc.translate('viewer_save_to_gallery')),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _saveToGallery(img);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: Text(loc.translate('viewer_share')),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _shareImage(img);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(loc.translate('viewer_copy_path')),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _copyPath(img);
              },
            ),
            const SizedBox(height: AppSpacing.s2),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToGallery(UiImage img) async {
    final loc = AppLocalizations.of(context);
    try {
      if (img.filePath != null && img.filePath!.isNotEmpty) {
        await ImageGallerySaver.saveFile(img.filePath!);
      } else if (img.bytes != null) {
        await ImageGallerySaver.saveImage(img.bytes!);
      } else {
        return;
      }
      if (mounted) {
        showAppSnack(
          context,
          message: loc.translate('viewer_saved'),
          kind: AppSnackKind.success,
        );
      }
    } on MissingPluginException {
      if (mounted) {
        showAppSnack(
          context,
          message: loc.translate('viewer_save_unavailable'),
          kind: AppSnackKind.error,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnack(
          context,
          message:
              loc.translate('viewer_save_failed').replaceAll('%s', '$e'),
          kind: AppSnackKind.error,
        );
      }
    }
  }

  Future<void> _shareImage(UiImage img) async {
    final loc = AppLocalizations.of(context);
    try {
      if (img.filePath != null && img.filePath!.isNotEmpty) {
        await Share.shareXFiles([XFile(img.filePath!)]);
        return;
      }
      if (img.bytes != null) {
        final dir = await getTemporaryDirectory();
        final f = File(
          '${dir.path}/share_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await f.writeAsBytes(img.bytes!, flush: true);
        await Share.shareXFiles([XFile(f.path)]);
      }
    } catch (e) {
      if (mounted) {
        showAppSnack(
          context,
          message:
              loc.translate('viewer_share_failed').replaceAll('%s', '$e'),
          kind: AppSnackKind.error,
        );
      }
    }
  }

  Future<void> _copyPath(UiImage img) async {
    if (img.filePath == null || img.filePath!.isEmpty) return;
    final loc = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: img.filePath!));
    if (mounted) {
      showAppSnack(
        context,
        message: loc.translate('viewer_path_copied'),
        kind: AppSnackKind.success,
      );
    }
  }
}

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.filePath});

  final String filePath;

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
