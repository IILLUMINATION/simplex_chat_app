import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vthumb;
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';

import '../../main.dart';
import '../service/tanglex_service.dart';
import '../stickers/sticker_store.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatRef;
  final String chatName;
  final Uint8List? avatarImage;

  const ChatScreen({
    super.key,
    required this.chatRef,
    required this.chatName,
    this.avatarImage,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  List<_UiMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _sendingMedia = false;
  final Set<int> _autoRequestedFiles = <int>{};
  bool _autoDownloadEnabled = false;
  bool _enableFileReceive = false;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  Timer? _refreshDebounce;
  final AudioPlayer _audioPlayer = AudioPlayer();
  _AudioNowPlaying? _audioNowPlaying;
  final StickerStore _stickerStore = StickerStore.instance;
  bool _stickersLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadStickers();
    _eventSub =
        ref.read(tanglexServiceProvider).eventStream.listen(_handleEvent);
  }

  Future<void> _loadStickers() async {
    await _stickerStore.load();
    if (mounted) {
      setState(() => _stickersLoaded = true);
    }
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    final service = ref.read(tanglexServiceProvider);
    final msgs = await service.getChatMessages(widget.chatRef);
    final parsed = <_UiMessage>[];
    for (final raw in msgs) {
      final ui = _parseChatItem(raw);
      if (ui != null) parsed.add(ui);
    }
    parsed.sort((a, b) {
      final at = a.time ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.time ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at); // newest first
    });
    setState(() {
      _messages = parsed;
      _loading = false;
    });

    await _autoReceiveImages(parsed);
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _sending) return;

    _msgController.clear();
    setState(() => _sending = true);

    final service = ref.read(tanglexServiceProvider);
    final success = await service.sendMessage(widget.chatRef, text);

    if (success) {
      await _loadMessages();
    }

    setState(() => _sending = false);
  }

  Future<void> _sendImages() async {
    if (_sendingMedia) return;
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 90);
    if (files.isEmpty) return;
    setState(() => _sendingMedia = true);
    final service = ref.read(tanglexServiceProvider);
    final payload = <ImagePayload>[];
    for (final f in files) {
      final bytes = await f.readAsBytes();
      final preview = _makePreview(bytes);
      payload.add(ImagePayload(
        filePath: f.path,
        previewBytes: preview.bytes,
        previewMime: preview.mime,
      ));
    }
    final ok = await service.sendImages(widget.chatRef, payload);
    if (ok) {
      await _loadMessages();
    }
    setState(() => _sendingMedia = false);
  }

  Future<void> _pickVideo() async {
    if (_sendingMedia) return;
    final picker = ImagePicker();
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _sendingMedia = true);
    final bytes = await file.readAsBytes();
    final thumb = await vthumb.VideoThumbnail.thumbnailData(
      video: file.path,
      imageFormat: vthumb.ImageFormat.JPEG,
      maxWidth: 480,
      quality: 75,
    );
    final controller = VideoPlayerController.file(File(file.path));
    int durationSec = 0;
    try {
      await controller.initialize();
      durationSec = controller.value.duration.inSeconds;
    } catch (_) {}
    await controller.dispose();
    final previewBytes = thumb == null ? _prepareCirclePreview(bytes) : thumb;
    final service = ref.read(tanglexServiceProvider);
    final resultSend = await service.sendVideo(
      chatRef: widget.chatRef,
      filePath: file.path,
      previewBytes: previewBytes,
      durationSec: durationSec,
      isCircle: false,
    );
    if (resultSend.ok) {
      await _loadMessages();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resultSend.error == null
                ? 'Не удалось отправить видео'
                : 'Не удалось отправить: ${resultSend.error}',
          ),
        ),
      );
    }
    setState(() => _sendingMedia = false);
  }

  Future<void> _pickFile({bool audioOnly = false}) async {
    if (_sendingMedia) return;
    final res = await FilePicker.platform.pickFiles(
      type: audioOnly ? FileType.audio : FileType.any,
      withData: false,
    );
    if (res == null || res.files.isEmpty) return;
    final path = res.files.single.path;
    if (path == null) return;
    setState(() => _sendingMedia = true);
    final service = ref.read(tanglexServiceProvider);
    final resultSend = await service.sendFile(
      chatRef: widget.chatRef,
      filePath: path,
      text: '',
    );
    if (resultSend.ok) {
      await _loadMessages();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resultSend.error == null
                ? 'Не удалось отправить файл'
                : 'Не удалось отправить: ${resultSend.error}',
          ),
        ),
      );
    }
    setState(() => _sendingMedia = false);
  }

  Future<void> _sendSticker(StickerPack pack, StickerItem sticker) async {
    if (_sendingMedia) return;
    setState(() => _sendingMedia = true);
    _PreviewPayload preview;
    if (sticker.filePath.toLowerCase().endsWith('.webm')) {
      final thumb = await vthumb.VideoThumbnail.thumbnailData(
        video: sticker.filePath,
        imageFormat: vthumb.ImageFormat.JPEG,
        maxWidth: 160,
        quality: 55,
      );
      final safeThumb = thumb ?? _tinyPreview();
      preview = _compressPreview(
        _PreviewPayload(bytes: safeThumb, mime: 'image/jpeg'),
        maxBytes: 35000,
      );
    } else {
      final bytes = File(sticker.filePath).readAsBytesSync();
      preview = _compressPreview(_prepareStickerPreview(bytes), maxBytes: 35000);
    }
    final service = ref.read(tanglexServiceProvider);
    final result = await service.sendSticker(
      chatRef: widget.chatRef,
      filePath: sticker.filePath,
      previewBytes: preview.bytes,
      previewMime: preview.mime,
      packId: pack.id,
      stickerId: sticker.id,
    );
    if (result.ok) {
      await _loadMessages();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.error == null
                ? 'Не удалось отправить стикер'
                : 'Не удалось отправить: ${result.error}',
          ),
        ),
      );
    }
    setState(() => _sendingMedia = false);
  }

  void _openStickerPicker() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return _StickerPickerSheet(
          packs: _stickerStore.packs,
          onImport: () async {
            final res = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['sxpz', 'zip'],
            );
            if (res == null || res.files.isEmpty) return;
            final path = res.files.single.path;
            if (path == null) return;
            final pack = await _stickerStore.importZip(path);
            if (pack != null && mounted) {
              setState(() {});
            }
          },
          onCreate: () async {
            final created = await _createStickerPack();
            if (created != null && mounted) {
              setState(() {});
            }
          },
          onSend: (pack, item) {
            Navigator.of(ctx).pop();
            _sendSticker(pack, item);
          },
        );
      },
    );
  }

  Future<StickerPack?> _createStickerPack() async {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final authorCtrl = TextEditingController();
    StickerPack? created;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Новый стикер‑пак'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Название'),
                onChanged: (v) {
                  if (idCtrl.text.isEmpty) {
                    idCtrl.text = _slugify(v);
                  }
                },
              ),
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(labelText: 'ID (латиница)'),
              ),
              TextField(
                controller: authorCtrl,
                decoration: const InputDecoration(labelText: 'Автор (необяз.)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Далее'),
            ),
          ],
        );
      },
    );
    final name = nameCtrl.text.trim();
    final id = idCtrl.text.trim();
    if (name.isEmpty || id.isEmpty) return null;
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['webp', 'webm'],
      allowMultiple: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final paths =
        res.files.map((e) => e.path).whereType<String>().toList();
    created = await _stickerStore.createPack(
      packId: id,
      name: name,
      author: authorCtrl.text.trim().isEmpty ? null : authorCtrl.text.trim(),
      filePaths: paths,
    );
    return created;
  }

  void _openAttachMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo),
                title: const Text('Фото'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _sendImages();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Видео'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickVideo();
                },
              ),
              ListTile(
                leading: const Icon(Icons.music_note),
                title: const Text('Аудио'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickFile(audioOnly: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('Файл'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickFile(audioOnly: false);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _playAudio(_AudioItem audio) async {
    if (audio.filePath == null) return;
    try {
      if (_audioNowPlaying?.filePath != audio.filePath) {
        await _audioPlayer.setFilePath(audio.filePath!);
      }
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
      setState(() {
        _audioNowPlaying = _AudioNowPlaying(
          filePath: audio.filePath!,
          title: audio.title,
        );
      });
    } catch (_) {}
  }

  void _openMedia(List<_UiImage> images, int index) {
    final img = images[index];
    if (img.isVideo) {
      if (!img.isCircle) {
        _openVideoPlayer(context, img);
      }
      return;
    }
    _openGallery(context, images, index);
  }

  Future<void> _openCircleRecorder() async {
    if (_sendingMedia) return;
    final result = await Navigator.of(context).push<_CircleVideoResult>(
      MaterialPageRoute(
        builder: (_) => const _CircleRecorderScreen(),
        fullscreenDialog: true,
      ),
    );
    if (result == null) return;
    setState(() => _sendingMedia = true);
    final service = ref.read(tanglexServiceProvider);
    final resultSend = await service.sendVideo(
      chatRef: widget.chatRef,
      filePath: result.filePath,
      previewBytes: result.previewBytes,
      durationSec: result.durationSec,
      isCircle: true,
    );
    if (resultSend.ok) {
      await _loadMessages();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resultSend.error == null
                ? 'Не удалось отправить кружок'
                : 'Не удалось отправить: ${resultSend.error}',
          ),
        ),
      );
    }
    setState(() => _sendingMedia = false);
  }

  void _handleEvent(Map<String, dynamic> event) {
    final result = event['result'];
    if (result is! Map<String, dynamic>) return;
    final type = result['type'] as String?;
    if (type == null) return;

    final chatItems = <Map<String, dynamic>>[];
    if (result['chatItem'] is Map<String, dynamic>) {
      chatItems.add(Map<String, dynamic>.from(result['chatItem']));
    }
    if (result['chatItems'] is List) {
      for (final item in result['chatItems'] as List) {
        if (item is Map<String, dynamic>) {
          chatItems.add(Map<String, dynamic>.from(item));
        }
      }
    }
    if (chatItems.isEmpty) return;

    for (final item in chatItems) {
      final chatInfo = item['chatInfo'] as Map<String, dynamic>?;
      if (chatInfo == null) continue;
      final ref = _chatRefFromInfo(chatInfo);
      if (ref == widget.chatRef) {
        _scheduleRefresh();
        return;
      }
    }
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        _loadMessages();
      }
    });
  }

  List<Widget> _buildDisplayItems(List<_UiMessage> messages) {
    final items = <Widget>[];
    int i = 0;
    while (i < messages.length) {
      final m = messages[i];
      if (!m.isSystem && m.images.isNotEmpty) {
        final group = <_UiMessage>[m];
        int j = i + 1;
        while (j < messages.length) {
          final next = messages[j];
        final canGroup = !next.isSystem &&
            next.images.isNotEmpty &&
            next.fromMe == m.fromMe &&
            (next.text.isEmpty) &&
            (m.text.isEmpty) &&
            !next.images.any((e) => e.isVideo || e.isCircle) &&
            !m.images.any((e) => e.isVideo || e.isCircle) &&
            !next.images.any((e) => e.isSticker) &&
            !m.images.any((e) => e.isSticker) &&
            _closeInTime(m.time, next.time, const Duration(minutes: 5));
          if (!canGroup) break;
          group.add(next);
          j++;
        }
        final allImages = group.expand((g) => g.images).toList();
        final text = m.text;
        items.add(_MessageBubble(
          message: _UiMessage(
            text: text,
            fromMe: m.fromMe,
            timeStr: m.timeStr,
            status: m.status,
            isSystem: false,
            images: allImages,
            time: m.time,
          ),
          onDownloadImage: _requestFullImage,
          onOpenMedia: _openMedia,
          onPlayAudio: _playAudio,
        ));
        i = j;
        continue;
      }
      items.add(m.isSystem
          ? _SystemBubble(text: m.text)
          : _MessageBubble(
              message: m,
              onDownloadImage: _requestFullImage,
              onOpenMedia: _openMedia,
              onPlayAudio: _playAudio,
            ));
      i++;
    }
    return items;
  }

  Future<void> _autoReceiveImages(List<_UiMessage> parsed) async {
    if (!_autoDownloadEnabled || !_enableFileReceive) return;
    final service = ref.read(tanglexServiceProvider);
    bool anyAccepted = false;
    for (final m in parsed) {
      for (final img in m.images) {
        final fileId = img.fileId;
        if (fileId == null) continue;
        if (_autoRequestedFiles.contains(fileId)) continue;
        if (img.hasFullImage) continue;
        if (m.fromMe) continue;
        if (img.fileStatusType != 'rcvInvitation') continue;
        if (img.fileSize != null &&
            img.fileSize! > _maxAutoReceiveImageSize) {
          continue;
        }
        _autoRequestedFiles.add(fileId);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final ok =
            await service.receiveFile(fileId, approvedRelays: true);
        if (ok) {
          anyAccepted = true;
        }
      }
    }
    if (anyAccepted && mounted) {
      await _loadMessages();
    }
  }

  Future<void> _requestFullImage(_UiImage image) async {
    if (image.fileId == null) return;
    if (image.fileStatusType != 'rcvInvitation') return;
    if (!_enableFileReceive) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('HD download disabled (crash in native core).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final service = ref.read(tanglexServiceProvider);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await service.receiveFile(
      image.fileId!,
      approvedRelays: true,
      encrypt: true,
    );
  }

  @override
  void dispose() {
    _msgController.dispose();
    _audioPlayer.dispose();
    _eventSub?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = _initials(widget.chatName);
    final displayItems = _buildDisplayItems(_messages);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: 'HD download',
            icon: Icon(
              _enableFileReceive ? Icons.cloud_download : Icons.cloud_off,
            ),
            onPressed: () async {
              final enabled = await showModalBottomSheet<bool>(
                context: context,
                builder: (ctx) {
                  return SafeArea(
                    child: ListTile(
                      leading: Icon(
                        _enableFileReceive
                            ? Icons.cloud_download
                            : Icons.cloud_off,
                      ),
                      title: const Text('HD download (unstable)'),
                      subtitle: const Text(
                        'Включай только если нужно: может крэшить native core.',
                      ),
                      onTap: () => Navigator.of(ctx).pop(!_enableFileReceive),
                    ),
                  );
                },
              );
              if (enabled == null) return;
              setState(() => _enableFileReceive = enabled);
            },
          ),
        ],
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.primaryContainer,
              backgroundImage:
                  widget.avatarImage != null ? MemoryImage(widget.avatarImage!) : null,
              child: widget.avatarImage == null
                  ? Text(
                      initials,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.chatName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_audioNowPlaying != null)
            _AudioMiniPlayer(
              player: _audioPlayer,
              title: _audioNowPlaying!.title,
            ),
          // Messages list
          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.surface,
                        theme.colorScheme.surfaceContainerLowest,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ChatPatternPainter(
                      dotColor: theme.colorScheme.outline.withOpacity(0.08),
                    ),
                  ),
                ),
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                        ? Center(
                            child: Text(
                              'No messages yet',
                              style:
                                  TextStyle(color: theme.colorScheme.outline),
                            ),
                          )
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            itemCount: displayItems.length,
                            itemBuilder: (context, index) {
                              final item = displayItems[index];
                              return item;
                            },
                          ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Message input
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: _sendingMedia ? null : _openAttachMenu,
                      icon: const Icon(Icons.attach_file),
                    ),
                    IconButton(
                      onPressed: _sendingMedia ? null : _openStickerPicker,
                      icon: const Icon(Icons.emoji_emotions_outlined),
                    ),
                    IconButton(
                      onPressed: _sendingMedia ? null : _openCircleRecorder,
                      icon: const Icon(Icons.fiber_manual_record),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _msgController,
                        decoration: const InputDecoration(
                          hintText: 'Message...',
                          border: InputBorder.none,
                        ),
                        maxLines: 4,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      onPressed: _sending ? null : _sendMessage,
                      icon: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _UiMessage message;
  final void Function(_UiImage image) onDownloadImage;
  final void Function(List<_UiImage> images, int index) onOpenMedia;
  final void Function(_AudioItem audio) onPlayAudio;

  const _MessageBubble({
    required this.message,
    required this.onDownloadImage,
    required this.onOpenMedia,
    required this.onPlayAudio,
  });

  @override
  Widget build(BuildContext context) {
    final text = message.text;
    final fromMe = message.fromMe;
    final status = message.status;
    final timeStr = message.timeStr;
    final theme = Theme.of(context);
    final isVideoOnly = message.images.length == 1 &&
        message.images.first.isVideo &&
        message.images.first.isCircle &&
        text.isEmpty;
    final isStickerOnly = message.images.length == 1 &&
        message.images.first.isSticker &&
        text.isEmpty;
    final bubbleColor = isVideoOnly
        ? Colors.transparent
        : (fromMe
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest);
    final textColor = fromMe
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        padding: isVideoOnly || isStickerOnly
            ? const EdgeInsets.all(2)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(fromMe ? 18 : 6),
            bottomRight: Radius.circular(fromMe ? 6 : 18),
          ),
          boxShadow: (isVideoOnly || isStickerOnly)
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment:
              fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (message.audio != null) ...[
              _AudioBubble(
                audio: message.audio!,
                fromMe: fromMe,
                onPlay: () => onPlayAudio(message.audio!),
              ),
              const SizedBox(height: 6),
            ],
            if (message.images.isNotEmpty) ...[
              if (isStickerOnly)
                _StickerView(image: message.images.first)
              else
              _MediaGrid(
                images: message.images,
                fromMe: message.fromMe,
                onOpen: (i) => onOpenMedia(message.images, i),
                onDownload: (i) => onDownloadImage(message.images[i]),
              ),
              if (text.isNotEmpty) const SizedBox(height: 6),
            ],
            if (text.isNotEmpty)
              SelectableText(
                text,
                style: TextStyle(color: textColor, height: 1.25),
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (timeStr.isNotEmpty)
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                if (status.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemBubble extends StatelessWidget {
  final String text;

  const _SystemBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

class _AudioMiniPlayer extends StatelessWidget {
  final AudioPlayer player;
  final String title;

  const _AudioMiniPlayer({
    required this.player,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          StreamBuilder<PlayerState>(
            stream: player.playerStateStream,
            builder: (context, snap) {
              final playing = snap.data?.playing ?? false;
              return IconButton(
                onPressed: () => playing ? player.pause() : player.play(),
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              );
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
                StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, posSnap) {
                    final pos = posSnap.data ?? Duration.zero;
                    final dur = player.duration ?? Duration.zero;
                    final value = dur.inMilliseconds == 0
                        ? 0.0
                        : pos.inMilliseconds / dur.inMilliseconds;
                    return LinearProgressIndicator(value: value);
                  },
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => player.stop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _AudioBubble extends StatelessWidget {
  final _AudioItem audio;
  final bool fromMe;
  final VoidCallback onPlay;

  const _AudioBubble({
    required this.audio,
    required this.fromMe,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkResponse(
          onTap: audio.filePath == null ? null : onPlay,
          radius: 20,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.play_arrow,
              color: theme.colorScheme.onPrimaryContainer,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 180,
          child: Text(
            audio.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}

class _UiMessage {
  final String text;
  final bool fromMe;
  final String timeStr;
  final String status;
  final bool isSystem;
  final List<_UiImage> images;
  final DateTime? time;
  final _AudioItem? audio;

  const _UiMessage({
    required this.text,
    required this.fromMe,
    required this.timeStr,
    required this.status,
    required this.isSystem,
    required this.images,
    required this.time,
    this.audio,
  });
}

class _AudioItem {
  final String title;
  final String? filePath;

  const _AudioItem({
    required this.title,
    required this.filePath,
  });
}

class _AudioNowPlaying {
  final String filePath;
  final String title;

  const _AudioNowPlaying({
    required this.filePath,
    required this.title,
  });
}

class _StickerPickerSheet extends StatefulWidget {
  final List<StickerPack> packs;
  final VoidCallback onImport;
  final VoidCallback onCreate;
  final void Function(StickerPack pack, StickerItem item) onSend;

  const _StickerPickerSheet({
    required this.packs,
    required this.onImport,
    required this.onCreate,
    required this.onSend,
  });

  @override
  State<_StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<_StickerPickerSheet> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final packs = widget.packs;
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.55,
        child: Column(
          children: [
            if (packs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Стикеры не установлены',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: widget.onImport,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Импортировать'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: widget.onCreate,
                          icon: const Icon(Icons.add),
                          label: const Text('Создать'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 54,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: packs.length + 2,
                  itemBuilder: (context, index) {
                    if (index == packs.length) {
                      return IconButton(
                        onPressed: widget.onImport,
                        icon: const Icon(Icons.add),
                      );
                    }
                    if (index == packs.length + 1) {
                      return IconButton(
                        onPressed: widget.onCreate,
                        icon: const Icon(Icons.create),
                      );
                    }
                    final p = packs[index];
                    final selected = index == _selected;
                    return GestureDetector(
                      onTap: () => setState(() => _selected = index),
                      child: Container(
                        margin:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: selected
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: p.coverPath != null
                            ? Image.file(File(p.coverPath!))
                            : Center(
                                child: Text(
                                  p.name.characters.first,
                                  style: theme.textTheme.labelLarge,
                                ),
                              ),
                      ),
                    );
                  },
                ),
              ),
            const Divider(height: 1),
            if (packs.isNotEmpty)
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: packs[_selected].stickers.length,
                  itemBuilder: (context, index) {
                    final s = packs[_selected].stickers[index];
                    return GestureDetector(
                      onTap: () => widget.onSend(packs[_selected], s),
                      child: _StickerThumb(filePath: s.filePath),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

_UiMessage? _parseChatItem(Map<String, dynamic> msg) {
  final chatDir = msg['chatDir'] as Map<String, dynamic>?;
  final dirType = chatDir?['type'] as String? ?? '';
  final fromMe = dirType.endsWith('Snd');

  final meta = msg['meta'] as Map<String, dynamic>?;
  final statusObj = meta?['itemStatus'];
  final status = statusObj is Map ? (statusObj['type'] as String? ?? '') : '';
  final itemText = meta?['itemText'] as String?;
  final tsStr = meta?['itemTs'] as String?;
  String timeStr = '';
  DateTime? time;
  if (tsStr != null) {
    try {
      time = DateTime.parse(tsStr).toLocal();
      timeStr = DateFormat.Hm().format(time);
    } catch (_) {}
  }

  final content = msg['content'] as Map<String, dynamic>?;
  final contentType = content?['type'] as String?;
  if (contentType == 'chatBanner') {
    return _UiMessage(
      text: itemText ?? 'Chat started',
      fromMe: false,
      timeStr: '',
      status: '',
      isSystem: true,
      images: const [],
      time: time,
    );
  }

  if (contentType == 'sndMsgContent' || contentType == 'rcvMsgContent') {
    final msgContent = content?['msgContent'] as Map<String, dynamic>?;
    final msgType = msgContent?['type'] as String?;
    final text = msgContent?['text'] as String? ?? '';
    final imageData = msgContent?['image'] as String?;
    final durationSec = msgContent?['duration'] as int?;
    final images = <_UiImage>[];
    final fileObj = msg['file'] as Map<String, dynamic>?;
    final fileSource = fileObj?['fileSource'] as Map<String, dynamic>?;
    final filePath = fileSource?['filePath'] as String?;
    final fileId = fileObj?['fileId'] as int?;
    final fileSize = fileObj?['fileSize'] as int?;
    final fileStatus = fileObj?['fileStatus'] as Map<String, dynamic>?;
    final fileStatusType = fileStatus?['type'] as String?;
    final fileName = fileObj?['fileName'] as String?;
    final isCircle = (fileName != null && fileName.startsWith('circle_'));
    final isSticker = fileName != null && fileName.startsWith('st__');
    final isWebm = fileName != null && fileName.toLowerCase().endsWith('.webm');
    final audioItem = _parseAudio(fileName, filePath);
    final decoded = _decodeImage(imageData);
    final hasLocalFile = filePath != null && File(filePath).existsSync();
    if (msgType == 'video') {
      images.add(_UiImage(
        filePath: hasLocalFile ? filePath : null,
        bytes: decoded,
        fileId: fileId,
        fileSize: fileSize,
        fileStatusType: fileStatusType,
        isVideo: true,
        isCircle: isCircle,
        isSticker: isSticker,
        isWebm: isWebm,
        durationSec: durationSec,
      ));
    } else if (msgType == 'image') {
      images.add(_UiImage(
        filePath: hasLocalFile ? filePath : null,
        bytes: decoded,
        fileId: fileId,
        fileSize: fileSize,
        fileStatusType: fileStatusType,
        isSticker: isSticker,
        isWebm: isWebm,
      ));
    } else {
      if (hasLocalFile) {
        images.add(_UiImage(
          filePath: filePath,
          fileId: fileId,
          fileSize: fileSize,
          fileStatusType: fileStatusType,
          isVideo: false,
        ));
      } else if (decoded != null) {
        images.add(_UiImage(
          bytes: decoded,
          fileId: fileId,
          fileSize: fileSize,
          fileStatusType: fileStatusType,
          isVideo: false,
        ));
      }
    }
    if ((msgType == 'image' || msgType == 'video') &&
        isSticker &&
        images.isEmpty) {
      images.add(_UiImage(
        filePath: hasLocalFile ? filePath : null,
        bytes: decoded,
        fileId: fileId,
        fileSize: fileSize,
        fileStatusType: fileStatusType,
        isVideo: msgType == 'video',
        isSticker: true,
        isWebm: isWebm,
        durationSec: durationSec,
      ));
    }
    if (msgType == 'file' && audioItem != null) {
      return _UiMessage(
        text: '',
        fromMe: fromMe,
        timeStr: timeStr,
        status: status,
        isSystem: false,
        images: const [],
        time: time,
        audio: audioItem,
      );
    }
    String display = text;
    if (msgType == 'image') {
      display = text;
    } else if (msgType == 'video') {
      display = isCircle ? '' : text;
    } else if (msgType == 'voice') {
      display = text.isNotEmpty ? '🎤 $text' : '';
    } else if (msgType == 'file') {
      display = text.isNotEmpty ? '📎 $text' : '';
    } else if (msgType == 'link') {
      display = text;
    } else if (msgType == 'report') {
      display = text.isNotEmpty ? '🚩 $text' : '';
    } else if (msgType == 'chat') {
      display = text.isNotEmpty ? '💬 $text' : '';
    } else if (msgType == 'unknown') {
      display = text.isNotEmpty ? text : '[Unsupported]';
    }
    return _UiMessage(
      text: display.isNotEmpty ? display : (itemText ?? ''),
      fromMe: fromMe,
      timeStr: timeStr,
      status: status,
      isSystem: false,
      images: images,
      time: time,
    );
  }

  if (contentType != null) {
    final label = itemText ?? contentType;
    return _UiMessage(
      text: label,
      fromMe: false,
      timeStr: '',
      status: '',
      isSystem: true,
      images: const [],
      time: time,
    );
  }

  if (itemText != null && itemText.isNotEmpty) {
    return _UiMessage(
      text: itemText,
      fromMe: fromMe,
      timeStr: timeStr,
      status: status,
      isSystem: false,
      images: const [],
      time: time,
    );
  }

  return null;
}

_AudioItem? _parseAudio(String? fileName, String? filePath) {
  if (fileName == null) return null;
  final lower = fileName.toLowerCase();
  const exts = [
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.opus',
    '.flac'
  ];
  final isAudio = exts.any(lower.endsWith);
  if (!isAudio) return null;
  return _AudioItem(title: fileName, filePath: filePath);
}

bool _closeInTime(DateTime? a, DateTime? b, Duration delta) {
  if (a == null || b == null) return false;
  return (a.difference(b).abs() <= delta);
}

class _MediaGrid extends StatelessWidget {
  final List<_UiImage> images;
  final bool fromMe;
  final void Function(int index) onOpen;
  final void Function(int index) onDownload;

  const _MediaGrid({
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
        final child = img.isSticker
            ? _StickerView(image: img)
            : img.isVideo && img.isCircle
            ? _VideoCircle(
                image: img,
              )
            : img.isVideo
                ? _VideoThumbRect(image: img)
                : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildImage(img),
                    if (!img.hasFullImage &&
                        img.fileId != null &&
                        !fromMe &&
                        img.fileStatusType == 'rcvInvitation')
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: GestureDetector(
                          onTap: () => onDownload(index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'HD',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
        return GestureDetector(
          onTap: () => onOpen(index),
          child: child,
        );
      },
    );
  }

  Widget _buildImage(_UiImage img) {
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

void _openGallery(BuildContext context, List<_UiImage> images, int initial) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _GalleryView(images: images, initial: initial),
      fullscreenDialog: true,
    ),
  );
}

String _formatDuration(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(1, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

void _openVideoPlayer(BuildContext context, _UiImage image) {
  if (image.filePath == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Видео ещё не загружено.')),
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _VideoPlayerScreen(filePath: image.filePath!),
      fullscreenDialog: true,
    ),
  );
}

class _VideoPlayerScreen extends StatefulWidget {
  final String filePath;

  const _VideoPlayerScreen({required this.filePath});

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
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

class _GalleryView extends StatefulWidget {
  final List<_UiImage> images;
  final int initial;

  const _GalleryView({required this.images, required this.initial});

  @override
  State<_GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends State<_GalleryView> {
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
            child: Center(
                child: img.filePath != null
                  ? Image.file(
                      File(img.filePath!),
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: Colors.black12),
                    )
                  : Image.memory(
                      img.bytes!,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: Colors.black12),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _ChatPatternPainter extends CustomPainter {
  final Color dotColor;

  _ChatPatternPainter({required this.dotColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dotColor;
    const spacing = 32.0;
    const radius = 1.4;
    for (double y = 12; y < size.height; y += spacing) {
      for (double x = 12; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChatPatternPainter oldDelegate) {
    return oldDelegate.dotColor != dotColor;
  }
}

class _VideoCircle extends StatefulWidget {
  final _UiImage image;

  const _VideoCircle({required this.image});

  @override
  State<_VideoCircle> createState() => _VideoCircleState();
}

class _VideoCircleState extends State<_VideoCircle> {
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
  void didUpdateWidget(covariant _VideoCircle oldWidget) {
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
                      painter: _RingProgressPainter(
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _formatDuration(img.durationSec!),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
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

  Widget _previewBox(_UiImage img, double side) {
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
    final targetMs =
        (ctrl.value.duration.inMilliseconds * progress).toInt();
    ctrl.seekTo(Duration(milliseconds: targetMs));
    setState(() {});
  }
}

class _VideoThumbRect extends StatelessWidget {
  final _UiImage image;

  const _VideoThumbRect({required this.image});

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
              child: const Icon(Icons.play_arrow,
                  color: Colors.white, size: 26),
            ),
          ),
          if (image.durationSec != null)
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatDuration(image.durationSec!),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StickerView extends StatelessWidget {
  final _UiImage image;

  const _StickerView({required this.image});

  @override
  Widget build(BuildContext context) {
    const size = 140.0;
    Widget child;
    if (image.isWebm && image.filePath != null) {
      child = _StickerWebm(filePath: image.filePath!);
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

class _StickerThumb extends StatelessWidget {
  final String filePath;

  const _StickerThumb({required this.filePath});

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

class _StickerWebm extends StatefulWidget {
  final String filePath;

  const _StickerWebm({required this.filePath});

  @override
  State<_StickerWebm> createState() => _StickerWebmState();
}

class _StickerWebmState extends State<_StickerWebm> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller?.play();
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: ctrl.value.size.width,
        height: ctrl.value.size.height,
        child: VideoPlayer(ctrl),
      ),
    );
  }
}

class _RingProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double stroke;

  _RingProgressPainter({
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
  bool shouldRepaint(covariant _RingProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _CircleVideoResult {
  final String filePath;
  final Uint8List previewBytes;
  final int durationSec;

  const _CircleVideoResult({
    required this.filePath,
    required this.previewBytes,
    required this.durationSec,
  });
}

class _CircleRecorderScreen extends StatefulWidget {
  const _CircleRecorderScreen();

  @override
  State<_CircleRecorderScreen> createState() => _CircleRecorderScreenState();
}

class _CircleRecorderScreenState extends State<_CircleRecorderScreen> {
  CameraController? _controller;
  bool _loading = true;
  bool _recording = false;
  int _elapsedSec = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }
      final cam = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _elapsedSec = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSec += 1);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _toggleRecording() async {
    final ctrl = _controller;
    if (ctrl == null || _loading) return;
    if (_recording) {
      final file = await ctrl.stopVideoRecording();
      _stopTimer();
      setState(() => _recording = false);
      final duration = _elapsedSec;
      final thumb = await vthumb.VideoThumbnail.thumbnailData(
        video: file.path,
        imageFormat: vthumb.ImageFormat.JPEG,
        maxWidth: 480,
        quality: 75,
      );
      if (!mounted) return;
      if (thumb == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сделать превью')),
        );
        return;
      }
      final previewBytes = _prepareCirclePreview(thumb);
      Navigator.of(context).pop(
        _CircleVideoResult(
          filePath: file.path,
          previewBytes: previewBytes,
          durationSec: duration,
        ),
      );
    } else {
      await ctrl.startVideoRecording();
      setState(() => _recording = true);
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewSize = _controller?.value.previewSize;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Кружок'),
        actions: [
          if (_recording)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  _formatDuration(_elapsedSec),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
        ],
      ),
      body: _loading || _controller == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Spacer(),
                Center(
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _recording
                            ? Colors.redAccent
                            : theme.colorScheme.outline,
                        width: 3,
                      ),
                    ),
                    child: ClipOval(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: previewSize?.height ?? 480,
                          height: previewSize?.width ?? 640,
                          child: CameraPreview(_controller!),
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: GestureDetector(
                    onTap: _toggleRecording,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: _recording ? Colors.redAccent : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _recording ? Icons.stop : Icons.fiber_manual_record,
                        color: _recording ? Colors.white : Colors.redAccent,
                        size: 34,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

Uint8List? _decodeImage(String? dataUri) {
  if (dataUri == null || dataUri.isEmpty) return null;
  final marker = 'base64,';
  final idx = dataUri.indexOf(marker);
  if (idx == -1) return null;
  final b64 = dataUri.substring(idx + marker.length);
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

String _guessMime(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

_PreviewPayload _makePreview(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return _PreviewPayload(bytes: bytes, mime: 'image/jpeg');
    }
    final resized = img.copyResize(decoded, width: 192);
    final jpg = img.encodeJpg(resized, quality: 60);
    return _PreviewPayload(bytes: Uint8List.fromList(jpg), mime: 'image/jpeg');
  } catch (_) {
    return _PreviewPayload(bytes: bytes, mime: 'image/jpeg');
  }
}

class _PreviewPayload {
  final Uint8List bytes;
  final String mime;
  const _PreviewPayload({required this.bytes, required this.mime});
}

class _UiImage {
  final Uint8List? bytes;
  final String? filePath;
  final int? fileId;
  final int? fileSize;
  final String? fileStatusType;
  final bool isVideo;
  final bool isCircle;
  final bool isSticker;
  final bool isWebm;
  final int? durationSec;
  const _UiImage({
    this.bytes,
    this.filePath,
    this.fileId,
    this.fileSize,
    this.fileStatusType,
    this.isVideo = false,
    this.isCircle = false,
    this.isSticker = false,
    this.isWebm = false,
    this.durationSec,
  });

  bool get hasFullImage => filePath != null;
}

const int _maxAutoReceiveImageSize = 522240; // 255KB * 2 (TangleX iOS)

Uint8List _prepareCirclePreview(Uint8List input) {
  try {
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;
    final size = decoded.width < decoded.height
        ? decoded.width
        : decoded.height;
    final offsetX = (decoded.width - size) ~/ 2;
    final offsetY = (decoded.height - size) ~/ 2;
    final cropped = img.copyCrop(
      decoded,
      x: offsetX,
      y: offsetY,
      width: size,
      height: size,
    );
    final resized = img.copyResize(cropped, width: 320, height: 320);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
  } catch (_) {
    return input;
  }
}

_PreviewPayload _prepareStickerPreview(Uint8List input) {
  try {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      return _PreviewPayload(bytes: input, mime: 'image/jpeg');
    }
    final resized = img.copyResize(decoded, width: 160);
    final jpg = Uint8List.fromList(img.encodeJpg(resized, quality: 60));
    return _PreviewPayload(bytes: jpg, mime: 'image/jpeg');
  } catch (_) {
    return _PreviewPayload(bytes: input, mime: 'image/jpeg');
  }
}

_PreviewPayload _compressPreview(_PreviewPayload input, {int maxBytes = 35000}) {
  if (input.bytes.length <= maxBytes) return input;
  try {
    final decoded = img.decodeImage(input.bytes);
    if (decoded == null) return _PreviewPayload(bytes: _tinyPreview(), mime: 'image/jpeg');
    int size = 140;
    int quality = 55;
    Uint8List out = input.bytes;
    while (out.length > maxBytes && size >= 64) {
      final resized = img.copyResize(decoded, width: size);
      out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      size -= 16;
      quality = (quality - 5).clamp(30, 90);
    }
    return _PreviewPayload(bytes: out, mime: 'image/jpeg');
  } catch (_) {
    return _PreviewPayload(bytes: _tinyPreview(), mime: 'image/jpeg');
  }
}

Uint8List _tinyPreview() {
  final img1 = img.Image(width: 2, height: 2);
  img.fill(img1, color: img.ColorRgba8(136, 136, 136, 255));
  return Uint8List.fromList(img.encodeJpg(img1, quality: 50));
}

String _chatRefFromInfo(Map<String, dynamic> chatInfo) {
  final type = chatInfo['type'] as String?;
  if (type == 'direct') {
    final contact = chatInfo['contact'] as Map<String, dynamic>?;
    final contactId = contact?['contactId'] as int?;
    if (contactId != null) return '@$contactId';
  } else if (type == 'group') {
    final group = chatInfo['group'] as Map<String, dynamic>?;
    final groupId = group?['groupId'] as int?;
    if (groupId != null) return '#$groupId';
  } else if (type == 'contactRequest') {
    final req = chatInfo['contactRequest'] as Map<String, dynamic>?;
    final contactId = req?['contactId_'] as int?;
    if (contactId != null) return '<@$contactId';
  } else if (type == 'contactConnection') {
    final conn = chatInfo['contactConnection'] as Map<String, dynamic>?;
    final connId = conn?['connId'] as int?;
    if (connId != null) return '<@$connId';
  }
  return '';
}

String _slugify(String input) {
  final lower = input.toLowerCase();
  final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  return cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
}


String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  String firstChar(String s) =>
      String.fromCharCode(s.runes.isNotEmpty ? s.runes.first : 63);
  if (parts.length == 1) {
    return firstChar(parts.first).toUpperCase();
  }
  final first = firstChar(parts.first).toUpperCase();
  final last = firstChar(parts.last).toUpperCase();
  return '$first$last';
}
