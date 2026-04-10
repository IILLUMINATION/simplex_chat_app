import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vthumb;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:highlight/highlight.dart' as highlight;
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/swift.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/bash.dart';
import 'package:just_audio/just_audio.dart';

import '../../main.dart';
import '../data/pin_store.dart';
import '../localization/app_localizations.dart';
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
  final Map<String, GlobalObjectKey> _messageKeys = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  _AudioNowPlaying? _audioNowPlaying;
  final StickerStore _stickerStore = StickerStore.instance;
  final PinStore _pinStore = PinStore.instance;
  final ScrollController _scrollController = ScrollController();
  bool _stickersLoaded = false;
  int _selectedPackIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadStickers();
    _pinStore.load();
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
    _messageKeys.clear();
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

    // Автопин + вырезание команды из текста
    final pinPattern = RegExp(r'^/pin\s+');
    final shortPin = RegExp(r'^/p\s+');
    bool anyChanged = false;
    final cleaned = <_UiMessage>[];
    for (final m in parsed) {
      if (pinPattern.hasMatch(m.text) || shortPin.hasMatch(m.text)) {
        final actualText = m.text
            .replaceFirst(pinPattern, '')
            .replaceFirst(shortPin, '');
        // Закрепляем
        if (!_pinStore.isPinned(widget.chatRef, m.key)) {
          await _pinStore.pin(PinnedMessage(
            chatRef: widget.chatRef,
            key: m.key,
            text: actualText,
            imageFilePath: m.images.isNotEmpty
                ? m.images.first.filePath
                : null,
            timeStr: m.timeStr,
            pinnedAt: DateTime.now(),
          ));
        }
        // Создаём сообщение с чистым текстом
        cleaned.add(_UiMessage(
          key: m.key,
          text: actualText,
          fromMe: m.fromMe,
          timeStr: m.timeStr,
          status: m.status,
          isSystem: m.isSystem,
          images: m.images,
          time: m.time,
          audio: m.audio,
          fileName: m.fileName,
          fileSize: m.fileSize,
          filePath: m.filePath,
        ));
        anyChanged = true;
      } else {
        cleaned.add(m);
      }
    }
    if (anyChanged) {
      setState(() => _messages = cleaned);
    }

    await _autoReceiveImages(anyChanged ? cleaned : parsed);
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _sending) return;

    _msgController.clear();
    setState(() => _sending = true);

    // Обрабатываем /pin или /p команду
    final pinCommand = RegExp(r'^/pin\s+');
    final shortPin = RegExp(r'^/p\s+');
    final shouldPin = pinCommand.hasMatch(text) || shortPin.hasMatch(text);
    final actualText = shouldPin
        ? text.replaceFirst(pinCommand, '').replaceFirst(shortPin, '')
        : text;

    final service = ref.read(tanglexServiceProvider);
    final success = await service.sendMessage(widget.chatRef, actualText);

    if (success && shouldPin) {
      // После отправки ждём немного и закрепляем последнее сообщение
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadMessages();
      if (_messages.isNotEmpty) {
        final lastMsg = _messages.first; // reverse list, первое = последнее
        await _pinStore.pin(PinnedMessage(
          chatRef: widget.chatRef,
          key: lastMsg.key,
          text: lastMsg.text,
          imageFilePath: lastMsg.images.isNotEmpty
              ? lastMsg.images.first.filePath
              : null,
          timeStr: lastMsg.timeStr,
          pinnedAt: DateTime.now(),
        ));
      }
    } else if (success) {
      await _loadMessages();
    }

    setState(() => _sending = false);
  }

  Future<void> _sendImages() async {
    final loc = AppLocalizations.of(context);
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
    final loc = AppLocalizations.of(context);
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
                ? loc.translate('failed_send_video')
                : loc.translate('failed_send_error').replaceAll('%s', resultSend.error ?? ''),
          ),
        ),
      );
    }
    setState(() => _sendingMedia = false);
  }

  Future<void> _pickFile({bool audioOnly = false}) async {
    final loc = AppLocalizations.of(context);
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
                ? loc.translate('failed_send_file')
                : loc.translate('failed_send_error').replaceAll('%s', resultSend.error ?? ''),
          ),
        ),
      );
    }
    setState(() => _sendingMedia = false);
  }

  Future<void> _sendSticker(StickerPack pack, StickerItem sticker) async {
    final loc = AppLocalizations.of(context);
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
                ? loc.translate('failed_send_sticker')
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
          onExport: _selectedPackIndex >= 0
              ? () async {
                  if (_selectedPackIndex < _stickerStore.packs.length) {
                    final pack = _stickerStore.packs[_selectedPackIndex];
                    final path = await _stickerStore.exportPack(packId: pack.id);
                    if (path != null && mounted) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Exported to $path')),
                        );
                      }
                    }
                  }
                }
              : null,
          onPackSelected: (index) {
            setState(() => _selectedPackIndex = index);
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
    final loc = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final authorCtrl = TextEditingController();
    StickerPack? created;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(loc.translate('new_sticker_pack')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: loc.translate('sticker_name')),
                onChanged: (v) {
                  if (idCtrl.text.isEmpty) {
                    idCtrl.text = _slugify(v);
                  }
                },
              ),
              TextField(
                controller: idCtrl,
                decoration: InputDecoration(labelText: loc.translate('sticker_id')),
              ),
              TextField(
                controller: authorCtrl,
                decoration: InputDecoration(labelText: loc.translate('sticker_author')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(loc.translate('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(loc.translate('sticker_next')),
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
    final loc = AppLocalizations.of(context);
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
                title: Text(loc.translate('photo')),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _sendImages();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: Text(loc.translate('video')),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickVideo();
                },
              ),
              ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(loc.translate('audio')),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickFile(audioOnly: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(loc.translate('file')),
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
    final loc = AppLocalizations.of(context);
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
                ? loc.translate('failed_send_circle')
                : loc.translate('failed_send_error').replaceAll('%s', resultSend.error ?? ''),
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
        items.add(_buildMessageBubble(_UiMessage(
          key: 'group_${m.key}',
          text: text,
          fromMe: m.fromMe,
          timeStr: m.timeStr,
          status: m.status,
          isSystem: false,
          images: allImages,
          time: m.time,
        )));
        i = j;
        continue;
      }
      items.add(m.isSystem
          ? _SystemBubble(text: m.text)
          : _buildMessageBubble(m));
      i++;
    }
    return items;
  }

  Widget _buildMessageBubble(_UiMessage m) {
    final isPinned = _pinStore.isPinned(widget.chatRef, m.key);
    final gKey = GlobalObjectKey(m.key);
    _messageKeys[m.key] = gKey;
    return KeyedSubtree(
      key: gKey,
      child: _MessageBubble(
        message: m,
        onDownloadImage: _requestFullImage,
        onOpenMedia: _openMedia,
        onPlayAudio: _playAudio,
        isPinned: isPinned,
        audioPlayer: _audioPlayer,
        nowPlaying: _audioNowPlaying,
        onTap: () => _showMessageOptions(context, m, isPinned),
      ),
    );
  }

  void _scrollToMessage(String msgKey) {
    if (!_scrollController.hasClients) return;

    // Ищем индекс в _messages
    final idx = _messages.indexWhere((m) => m.key == msgKey);
    if (idx < 0) return;

    // Приблизительный скролл
    final estimatedOffset = idx * 80.0;
    final maxOffset = _scrollController.position.maxScrollExtent;
    final target = estimatedOffset.clamp(0.0, maxOffset);

    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _showMessageOptions(
    BuildContext ctx,
    _UiMessage m,
    bool isPinned,
  ) async {
    final renderBox = ctx.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenH = MediaQuery.of(ctx).size.height;
    final screenW = MediaQuery.of(ctx).size.width;
    final menuW = 200.0;

    // Позиция: по центру сообщения, над или под ним
    final centerX = position.dx + size.width / 2;
    final menuY = position.dy < screenH / 2
        ? position.dy + size.height
        : position.dy - 200;

    await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromSize(
        Rect.fromLTWH(
          (centerX - menuW / 2).clamp(10.0, screenW - menuW),
          menuY.clamp(10.0, screenH - 200),
          menuW,
          200,
        ),
        Size(screenW, screenH),
      ),
      items: [
        if (m.text.isNotEmpty || m.images.isNotEmpty)
          PopupMenuItem<String>(
            value: 'pin',
            child: Row(
              children: [
                Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 20,
                  color: isPinned
                      ? Theme.of(ctx).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 12),
                Text(isPinned ? 'Открепить' : 'Закрепить'),
              ],
            ),
          ),
        if (m.text.isNotEmpty)
          const PopupMenuItem<String>(
            value: 'copy',
            child: Row(
              children: [
                Icon(Icons.copy, size: 20),
                SizedBox(width: 12),
                Text('Копировать'),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'reply',
          child: Row(
            children: [
              Icon(Icons.reply, size: 20),
              const SizedBox(width: 12),
              Text('Ответить'),
            ],
          ),
        ),
      ],
      elevation: 8,
    ).then((String? value) {
      if (value == 'pin') {
        if (isPinned) {
          _pinStore.unpin(widget.chatRef, m.key);
        } else {
          _pinStore.pin(PinnedMessage(
            chatRef: widget.chatRef,
            key: m.key,
            text: m.text,
            imageFilePath:
                m.images.isNotEmpty ? m.images.first.filePath : null,
            timeStr: m.timeStr,
            pinnedAt: DateTime.now(),
          ));
        }
        setState(() {});
      } else if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: m.text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Скопировано')),
          );
        }
      } else if (value == 'reply') {
        _msgController.text = '> ${m.text.split('\n').first} \n';
        _msgController.selection = TextSelection.fromPosition(
          TextPosition(offset: _msgController.text.length),
        );
      }
    });
  }

  Future<void> _autoReceiveImages(List<_UiMessage> parsed) async {
    final loc = AppLocalizations.of(context);
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
    final loc = AppLocalizations.of(context);
    if (image.fileId == null) return;
    if (image.fileStatusType != 'rcvInvitation') return;
    if (!_enableFileReceive) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.translate('hd_download_tooltip')),
          backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
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
    _scrollController.dispose();
    _eventSub?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final initials = _initials(widget.chatName);
    final displayItems = _buildDisplayItems(_messages);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: loc.translate('hd_download'),
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
                      title: Text(loc.translate('hd_download_tooltip')),
                      subtitle: Text(
                        loc.translate('hd_download_warning'),
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
                              loc.translate('no_messages_yet'),
                              style:
                                  TextStyle(color: theme.colorScheme.outline),
                            ),
                          )
                        : Column(
                            children: [
                              if (_pinStore.getPinCount(widget.chatRef) > 0)
                                _PinnedBar(
                                  pinned: _pinStore.getPinned(widget.chatRef),
                                  onPinTap: (pm) {
                                    _scrollToMessage(pm.key);
                                  },
                                  onUnpin: (pm) {
                                    _pinStore.unpin(widget.chatRef, pm.key);
                                    setState(() {});
                                  },
                                ),
                              Expanded(
                                child: ListView.builder(
                                  controller: _scrollController,
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
                              ),
                            ],
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
                        decoration: InputDecoration(
                          hintText: loc.translate('message_hint'),
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
  final bool isPinned;
  final AudioPlayer audioPlayer;
  final _AudioNowPlaying? nowPlaying;
  final VoidCallback? onTap;

  const _MessageBubble({
    required this.message,
    required this.onDownloadImage,
    required this.onOpenMedia,
    required this.onPlayAudio,
    this.isPinned = false,
    required this.audioPlayer,
    required this.nowPlaying,
    this.onTap,
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
    final hasSticker = message.images.any((e) => e.isSticker);
    final bubbleColor = isVideoOnly || isStickerOnly
        ? Colors.transparent
        : (fromMe
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest);
    final textColor = fromMe
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        padding: isVideoOnly || isStickerOnly
            ? const EdgeInsets.all(2)
            : (hasSticker
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: hasSticker ? Colors.transparent : bubbleColor,
          borderRadius: hasSticker
              ? null
              : BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(fromMe ? 18 : 6),
            bottomRight: Radius.circular(fromMe ? 6 : 18),
          ),
          boxShadow: (isVideoOnly || isStickerOnly || hasSticker)
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
            if (message.fileName != null && message.audio == null) ...[
              // Показываем файл ТОЛЬКО если это НЕ аудио
              _FileAttachment(
                fileName: message.fileName!,
                fileSize: message.fileSize,
                filePath: message.filePath,
                fromMe: fromMe,
              ),
              if (text.isNotEmpty) const SizedBox(height: 6),
            ],
            if (message.audio != null) ...[
              _AudioBubble(
                audio: message.audio!,
                fromMe: fromMe,
                onPlay: () => onPlayAudio(message.audio!),
                audioPlayer: audioPlayer,
                nowPlaying: nowPlaying,
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
              _MarkdownText(
                text: text,
                textColor: textColor,
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isPinned) ...[
                  Icon(
                    Icons.push_pin,
                    size: 12,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 3),
                ],
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
      ), // GestureDetector
    );
  }
}

class _MarkdownText extends StatelessWidget {
  final String text;
  final Color textColor;

  const _MarkdownText({required this.text, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeBg =
        theme.brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
    final codeBorder = theme.colorScheme.outline.withOpacity(0.2);

    // Register languages for highlight
    final langs = {
      'dart': dart,
      'python': python,
      'py': python,
      'javascript': javascript,
      'js': javascript,
      'typescript': typescript,
      'ts': typescript,
      'go': go,
      'java': java,
      'kotlin': kotlin,
      'swift': swift,
      'rust': rust,
      'cpp': cpp,
      'c++': cpp,
      'c': cpp,
      'bash': bash,
      'sh': bash,
      'shell': bash,
    };
    for (final entry in langs.entries) {
      highlight.highlight.registerLanguage(entry.key, entry.value);
    }

    return SelectionArea(
      child: MarkdownBody(
        data: text,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(color: textColor, height: 1.25),
          code: TextStyle(
            backgroundColor: codeBg,
            color: theme.colorScheme.onSurface,
            fontFamily: 'monospace',
            fontSize: theme.textTheme.bodyMedium?.fontSize,
          ),
          blockquote: TextStyle(
            color: textColor.withOpacity(0.7),
            fontStyle: FontStyle.italic,
          ),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: theme.colorScheme.outline, width: 3),
            ),
          ),
        ),
        builders: {
          'code': _CodeBlockBuilder(codeBg, textColor, Theme.of(context)),
        },
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final Color codeBg;
  final Color textColor;
  final ThemeData theme;

  _CodeBlockBuilder(this.codeBg, this.textColor, this.theme);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final codeText = element.textContent;
    if (codeText.isEmpty) return null;

    String? language;
    final classes = element.attributes['class'];
    if (classes != null) {
      final match = RegExp(r'language-(\w+)').firstMatch(classes);
      language = match?.group(1);
    }

    Widget codeWidget;
    if (language != null) {
      // Syntax highlighted code
      try {
        final result = highlight.highlight.parse(codeText.trim(), language: language);
        final html = result?.toHtml() ?? '';
        // Use simple styled text since we can't render HTML directly
        codeWidget = _HighlightedCodeBlock(
          text: codeText.trim(),
          language: language,
          textColor: textColor,
          codeBg: codeBg,
        );
      } catch (_) {
        codeWidget = _SimpleCodeBlock(
          text: codeText.trim(),
          textColor: textColor,
          codeBg: codeBg,
        );
      }
    } else {
      codeWidget = _SimpleCodeBlock(
        text: codeText.trim(),
        textColor: textColor,
        codeBg: codeBg,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: codeWidget,
    );
  }
}

class _HighlightedCodeBlock extends StatelessWidget {
  final String text;
  final String language;
  final Color textColor;
  final Color codeBg;

  const _HighlightedCodeBlock({
    required this.text,
    required this.language,
    required this.textColor,
    required this.codeBg,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = highlight.highlight.parse(text, language: language);
    final spans = _buildSpans(result?.nodes ?? [], theme);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText.rich(
        TextSpan(children: spans, style: const TextStyle(fontFamily: 'monospace')),
      ),
    );
  }

  List<TextSpan> _buildSpans(List<highlight.Node> nodes, ThemeData theme) {
    final spans = <TextSpan>[];
    final colorMap = _getCodeColors(theme: theme);
    for (final node in nodes) {
      if (node.value != null) {
        spans.add(TextSpan(
          text: node.value,
          style: TextStyle(
            color: node.className != null
                ? (colorMap[node.className] ?? textColor)
                : textColor,
          ),
        ));
      } else if (node.children != null) {
        spans.addAll(_buildSpans(node.children!, theme));
      }
    }
    return spans;
  }

  Map<String, Color> _getCodeColors({required ThemeData theme}) {
    return {
      'keyword': theme.colorScheme.primary,
      'string': const Color(0xFF2E7D32),
      'number': const Color(0xFF1565C0),
      'comment': theme.colorScheme.outline,
      'function': const Color(0xFF6A1B9A),
      'class': const Color(0xFFE65100),
      'built_in': theme.colorScheme.secondary,
      'type': const Color(0xFF00838F),
    };
  }
}

class _SimpleCodeBlock extends StatelessWidget {
  final String text;
  final Color textColor;
  final Color codeBg;

  const _SimpleCodeBlock({
    required this.text,
    required this.textColor,
    required this.codeBg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          color: textColor,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _PinnedBar extends StatefulWidget {
  final List<PinnedMessage> pinned;
  final void Function(PinnedMessage) onPinTap;
  final void Function(PinnedMessage) onUnpin;

  const _PinnedBar({
    required this.pinned,
    required this.onPinTap,
    required this.onUnpin,
  });

  @override
  State<_PinnedBar> createState() => _PinnedBarState();
}

class _PinnedBarState extends State<_PinnedBar> {
  late PageController _pageCtrl;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void didUpdateWidget(_PinnedBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Если количество пинов изменилось, сбрасываем страницу
    if (widget.pinned.length != oldWidget.pinned.length) {
      if (_currentPage >= widget.pinned.length) {
        _currentPage = widget.pinned.isEmpty
            ? 0
            : widget.pinned.length - 1;
        _pageCtrl.jumpToPage(_currentPage);
      }
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pins = widget.pinned;
    if (pins.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.15),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            child: PageView.builder(
              controller: _pageCtrl,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemCount: pins.length,
              itemBuilder: (context, index) {
                final pm = pins[index];
                return GestureDetector(
                  onTap: () => widget.onPinTap(pm),
                  child: Row(
                    children: [
                      Icon(Icons.push_pin, size: 16,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          pm.text.isNotEmpty
                              ? (pm.text.length > 60
                                  ? '${pm.text.substring(0, 60)}…'
                                  : pm.text)
                              : '📷 ${pm.timeStr}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (pins.length > 1) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${index + 1}/${pins.length}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontSize: 10,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => widget.onUnpin(pm),
                        child: Icon(Icons.close, size: 16,
                            color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (pins.length > 1) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                pins.length,
                (i) => Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.outline.withOpacity(
                      _currentPage == i ? 0.8 : 0.3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
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

class _FileAttachment extends StatelessWidget {
  final String fileName;
  final int? fileSize;
  final String? filePath;
  final bool fromMe;

  const _FileAttachment({
    required this.fileName,
    this.fileSize,
    this.filePath,
    required this.fromMe,
  });

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _fileIcon() {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.zip') || lower.endsWith('.sxpz') || lower.endsWith('.rar') || lower.endsWith('.7z') || lower.endsWith('.tar') || lower.endsWith('.gz')) return Icons.folder_zip;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return Icons.table_chart;
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return Icons.slideshow;
    if (lower.endsWith('.txt')) return Icons.text_snippet;
    if (lower.endsWith('.apk')) return Icons.android;
    if (lower.endsWith('.mp3') || lower.endsWith('.ogg') || lower.endsWith('.wav') || lower.endsWith('.flac') || lower.endsWith('.aac') || lower.endsWith('.m4a')) return Icons.audiotrack;
    if (lower.endsWith('.mp4') || lower.endsWith('.mkv') || lower.endsWith('.avi') || lower.endsWith('.mov') || lower.endsWith('.webm')) return Icons.movie;
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.gif') || lower.endsWith('.webp') || lower.endsWith('.svg') || lower.endsWith('.bmp')) return Icons.image;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = fromMe
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_fileIcon(), size: 24, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: iconColor,
                  ),
                ),
                if (fileSize != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatSize(fileSize!),
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (filePath != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 20),
              onPressed: () async {
                final uri = Uri.file(filePath!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
              splashRadius: 20,
            ),
          ],
        ],
      ),
    );
  }
}

class _AudioBubble extends StatelessWidget {
  final _AudioItem audio;
  final bool fromMe;
  final VoidCallback onPlay;
  final AudioPlayer audioPlayer;
  final _AudioNowPlaying? nowPlaying;

  const _AudioBubble({
    required this.audio,
    required this.fromMe,
    required this.onPlay,
    required this.audioPlayer,
    required this.nowPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audioColor = fromMe
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    final isNowPlaying = nowPlaying?.filePath == audio.filePath;

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: isNowPlaying
            ? Border.all(color: theme.colorScheme.primary, width: 1.5)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkResponse(
                onTap: audio.filePath == null ? null : onPlay,
                radius: 20,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isNowPlaying ? Icons.pause : Icons.play_arrow,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      audio.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: audioColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isNowPlaying)
                      Text(
                        'Сейчас играет',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Слайдер ТОЛЬКО для активного трека
          if (isNowPlaying) ...[
            const SizedBox(height: 8),
            _AudioSlider(
              audioPlayer: audioPlayer,
              theme: theme,
            ),
          ],
        ],
      ),
    );
  }
}

/// Отдельный StatefulWidget для слайдера — только для играющего трека
class _AudioSlider extends StatefulWidget {
  final AudioPlayer audioPlayer;
  final ThemeData theme;

  const _AudioSlider({required this.audioPlayer, required this.theme});

  @override
  State<_AudioSlider> createState() => _AudioSliderState();
}

class _AudioSliderState extends State<_AudioSlider> {
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;

  @override
  void initState() {
    super.initState();
    _posSub = widget.audioPlayer.positionStream.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
    _durSub = widget.audioPlayer.durationStream.listen((d) {
      if (mounted) setState(() => _dur = d ?? Duration.zero);
    });
    // Начальные значения
    _pos = widget.audioPlayer.position;
    _dur = widget.audioPlayer.duration ?? Duration.zero;
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _dur.inMilliseconds == 0
        ? 0.0
        : (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0);

    return Row(
      children: [
        Text(
          _fmt(_pos),
          style: TextStyle(fontSize: 11, color: widget.theme.colorScheme.outline),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value,
              onChanged: _dur.inMilliseconds > 0
                  ? (val) {
                      final ms = (val * _dur.inMilliseconds).toInt();
                      widget.audioPlayer.seek(Duration(milliseconds: ms));
                    }
                  : null,
            ),
          ),
        ),
        Text(
          _fmt(_dur),
          style: TextStyle(fontSize: 11, color: widget.theme.colorScheme.outline),
        ),
      ],
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _UiMessage {
  final String key; // уникальный ключ для pin
  final String text;
  final bool fromMe;
  final String timeStr;
  final String status;
  final bool isSystem;
  final List<_UiImage> images;
  final DateTime? time;
  final _AudioItem? audio;
  final String? fileName;
  final int? fileSize;
  final String? filePath;

  const _UiMessage({
    required this.key,
    required this.text,
    required this.fromMe,
    required this.timeStr,
    required this.status,
    required this.isSystem,
    required this.images,
    required this.time,
    this.audio,
    this.fileName,
    this.fileSize,
    this.filePath,
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
  final VoidCallback? onExport;
  final void Function(int index) onPackSelected;
  final void Function(StickerPack pack, StickerItem item) onSend;

  const _StickerPickerSheet({
    required this.packs,
    required this.onImport,
    required this.onCreate,
    this.onExport,
    required this.onPackSelected,
    required this.onSend,
  });

  @override
  State<_StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<_StickerPickerSheet> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
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
                      loc.translate('sticker_not_installed'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: widget.onImport,
                          icon: const Icon(Icons.upload_file),
                          label: Text(loc.translate('import')),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: widget.onCreate,
                          icon: const Icon(Icons.add),
                          label: Text(loc.translate('create')),
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
                  itemCount: packs.length + 3,
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
                    if (index == packs.length + 2) {
                      return IconButton(
                        onPressed: widget.onExport,
                        icon: const Icon(Icons.share),
                      );
                    }
                    final p = packs[index];
                    final selected = index == _selected;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selected = index);
                        widget.onPackSelected(index);
                      },
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
                            ? _StickerThumb(filePath: p.coverPath!)
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
  final msgKey = '${dirType}_${tsStr ?? ''}_${itemText ?? ''}';
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
      key: 'banner_$tsStr',
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
    } else if (msgType != 'file') {
      // Для file — не добавляем в images, используем fileName/fileSize/filePath
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
        key: msgKey,
        text: '',
        fromMe: fromMe,
        timeStr: timeStr,
        status: status,
        isSystem: false,
        images: const [],
        time: time,
        audio: audioItem,
        fileName: fileName,
        fileSize: fileSize,
        filePath: filePath,
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
      display = text.isNotEmpty ? text : '';
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
      key: msgKey,
      text: display.isNotEmpty ? display : (itemText ?? ''),
      fromMe: fromMe,
      timeStr: timeStr,
      status: status,
      isSystem: false,
      images: images,
      time: time,
      fileName: msgType == 'file' ? fileName : null,
      fileSize: msgType == 'file' ? fileSize : null,
      filePath: msgType == 'file' ? filePath : null,
    );
  }

  if (contentType != null) {
    final label = itemText ?? contentType;
    return _UiMessage(
      key: 'other_${tsStr ?? ''}',
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
      key: msgKey,
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
  final loc = AppLocalizations.of(context);
  if (image.filePath == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.translate('video_not_loaded'))),
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

  Widget _galleryImage(_UiImage img) {
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
            child: Center(
                child: _galleryImage(img),
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

class _StickerWebm extends StatelessWidget {
  final String filePath;

  const _StickerWebm({required this.filePath});

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
    final loc = AppLocalizations.of(context);
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
          SnackBar(content: Text(loc.translate('preview_error'))),
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
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final previewSize = _controller?.value.previewSize;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(loc.translate('circle')),
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
