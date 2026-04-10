import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../main.dart';
import '../../data/pin_store.dart';
import '../../localization/app_localizations.dart';
import '../../service/tanglex_service.dart' show TanglexService, ImagePayload;
import '../../stickers/sticker_store.dart' show StickerStore, StickerPack, StickerItem;
import 'chat_widgets.dart';
import 'package:just_audio/just_audio.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatRef;
  final String chatName;

  const ChatScreen({
    super.key,
    required this.chatRef,
    required this.chatName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  List<UiMessage> _messages = [];
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
  AudioNowPlaying? _audioNowPlaying;
  final StickerStore _stickerStore = StickerStore.instance;
  final PinStore _pinStore = PinStore.instance;
  final ScrollController _scrollController = ScrollController();
  int _selectedPackIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _pinStore.load();
    _eventSub = ref.read(tanglexServiceProvider).eventStream.listen(_handleEvent);
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    _messageKeys.clear();
    final service = ref.read(tanglexServiceProvider);
    final msgs = await service.getChatMessages(widget.chatRef);
    final parsed = <UiMessage>[];
    for (final raw in msgs) {
      final ui = parseChatItem(raw);
      if (ui != null) parsed.add(ui);
    }
    parsed.sort((a, b) {
      final at = a.time ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.time ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    setState(() {
      _messages = parsed;
      _loading = false;
    });

    final pinPattern = RegExp(r'^/pin\s+');
    final shortPin = RegExp(r'^/p\s+');
    bool anyChanged = false;
    final cleaned = <UiMessage>[];
    for (final m in parsed) {
      if (pinPattern.hasMatch(m.text) || shortPin.hasMatch(m.text)) {
        final actualText = m.text
            .replaceFirst(pinPattern, '')
            .replaceFirst(shortPin, '');
        if (!_pinStore.isPinned(widget.chatRef, m.key)) {
          await _pinStore.pin(PinnedMessage(
            chatRef: widget.chatRef,
            key: m.key,
            text: actualText,
            imageFilePath: m.images.isNotEmpty ? m.images.first.filePath : null,
            timeStr: m.timeStr,
            pinnedAt: DateTime.now(),
          ));
        }
        cleaned.add(UiMessage(
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

    final pinCommand = RegExp(r'^/pin\s+');
    final shortPin = RegExp(r'^/p\s+');
    final shouldPin = pinCommand.hasMatch(text) || shortPin.hasMatch(text);
    final actualText = shouldPin
        ? text.replaceFirst(pinCommand, '').replaceFirst(shortPin, '')
        : text;

    final service = ref.read(tanglexServiceProvider);
    final success = await service.sendMessage(widget.chatRef, actualText);

    if (success && shouldPin) {
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadMessages();
      if (_messages.isNotEmpty) {
        final lastMsg = _messages.first;
        await _pinStore.pin(PinnedMessage(
          chatRef: widget.chatRef,
          key: lastMsg.key,
          text: lastMsg.text,
          imageFilePath: lastMsg.images.isNotEmpty ? lastMsg.images.first.filePath : null,
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
    if (_sendingMedia) return;
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 90);
    if (files.isEmpty) return;
    setState(() => _sendingMedia = true);
    final service = ref.read(tanglexServiceProvider);
    final payload = <ImagePayload>[];
    for (final f in files) {
      final bytes = await f.readAsBytes();
      final preview = makePreview(bytes);
      payload.add(ImagePayload(
        filePath: f.path,
        previewBytes: preview.bytes,
        previewMime: preview.mime,
      ));
    }
    final ok = await service.sendImages(widget.chatRef, payload);
    if (ok) await _loadMessages();
    setState(() => _sendingMedia = false);
  }

  Future<void> _pickVideo() async {
    final loc = AppLocalizations.of(context);
    if (_sendingMedia) return;
    final picker = ImagePicker();
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _sendingMedia = true);
    final service = ref.read(tanglexServiceProvider);
    final thumb = await _generateVideoThumb(file.path);
    final duration = await _getVideoDuration(file.path);
    final resultSend = await service.sendVideo(
      chatRef: widget.chatRef,
      filePath: file.path,
      previewBytes: thumb.bytes,
      durationSec: duration,
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
    final service = ref.read(tanglexServiceProvider);
    final preview = await _generateStickerPreview(sticker.filePath);
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
        return StickerPickerSheet(
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
            if (pack != null && mounted) setState(() {});
          },
          onCreate: () async {
            final created = await _createStickerPack();
            if (created != null && mounted) setState(() {});
          },
          onExport: _selectedPackIndex >= 0
              ? () async {
                  if (_selectedPackIndex < _stickerStore.packs.length) {
                    final pack = _stickerStore.packs[_selectedPackIndex];
                    final path = await _stickerStore.exportPack(packId: pack.id);
                    if (path != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Exported to $path')),
                      );
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
                    idCtrl.text = slugify(v);
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
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(loc.translate('cancel'))),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(loc.translate('sticker_next'))),
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
    final paths = res.files.map((e) => e.path).whereType<String>().toList();
    return await _stickerStore.createPack(
      packId: id,
      name: name,
      author: authorCtrl.text.trim().isEmpty ? null : authorCtrl.text.trim(),
      filePaths: paths,
    );
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
                onTap: () { Navigator.of(ctx).pop(); _sendImages(); },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: Text(loc.translate('video')),
                onTap: () { Navigator.of(ctx).pop(); _pickVideo(); },
              ),
              ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(loc.translate('audio')),
                onTap: () { Navigator.of(ctx).pop(); _pickFile(audioOnly: true); },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(loc.translate('file')),
                onTap: () { Navigator.of(ctx).pop(); _pickFile(audioOnly: false); },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _playAudio(AudioItem audio) async {
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
        _audioNowPlaying = AudioNowPlaying(filePath: audio.filePath!, title: audio.title);
      });
    } catch (_) {}
  }

  void _openMedia(List<UiImage> images, int index) {
    final img = images[index];
    if (img.isVideo && !img.isCircle) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(filePath: img.filePath!),
          fullscreenDialog: true,
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GalleryView(images: images, initial: index),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openCircleRecorder() async {
    final loc = AppLocalizations.of(context);
    if (_sendingMedia) return;
    final result = await Navigator.of(context).push<CircleVideoResult>(
      MaterialPageRoute(
        builder: (_) => const CircleRecorderScreen(),
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
        if (item is Map<String, dynamic>) chatItems.add(Map<String, dynamic>.from(item));
      }
    }
    if (chatItems.isEmpty) return;

    for (final item in chatItems) {
      final chatInfo = item['chatInfo'] as Map<String, dynamic>?;
      if (chatInfo == null) continue;
      final ref = chatRefFromInfo(chatInfo);
      if (ref == widget.chatRef) {
        _scheduleRefresh();
        return;
      }
    }
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _loadMessages();
    });
  }

  List<Widget> _buildDisplayItems(List<UiMessage> messages) {
    final items = <Widget>[];
    DateTime? lastDate;
    int i = 0;
    while (i < messages.length) {
      final m = messages[i];

      if (m.time != null) {
        final msgDate = DateTime(m.time!.year, m.time!.month, m.time!.day);
        if (lastDate == null || msgDate != lastDate) {
          items.add(DateDivider(date: m.time!));
          lastDate = msgDate;
        }
      }

      if (!m.isSystem && m.images.isNotEmpty) {
        final group = <UiMessage>[m];
        int j = i + 1;
        while (j < messages.length) {
          final next = messages[j];
          final canGroup = !next.isSystem &&
              next.images.isNotEmpty &&
              next.fromMe == m.fromMe &&
              next.text.isEmpty &&
              m.text.isEmpty &&
              !next.images.any((e) => e.isVideo || e.isCircle) &&
              !m.images.any((e) => e.isVideo || e.isCircle) &&
              !next.images.any((e) => e.isSticker) &&
              !m.images.any((e) => e.isSticker) &&
              closeInTime(m.time, next.time, const Duration(minutes: 5));
          if (!canGroup) break;
          group.add(next);
          j++;
        }
        final allImages = group.expand((g) => g.images).toList();
        items.add(_buildMessageBubble(UiMessage(
          key: 'group_${m.key}',
          text: m.text,
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
      items.add(m.isSystem ? SystemBubble(text: m.text) : _buildMessageBubble(m));
      i++;
    }
    return items;
  }

  Widget _buildMessageBubble(UiMessage m) {
    final isPinned = _pinStore.isPinned(widget.chatRef, m.key);
    final gKey = GlobalObjectKey(m.key);
    _messageKeys[m.key] = gKey;
    return KeyedSubtree(
      key: gKey,
      child: MessageBubble(
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
    final idx = _messages.indexWhere((m) => m.key == msgKey);
    if (idx < 0) return;
    final estimatedOffset = idx * 80.0;
    final maxOffset = _scrollController.position.maxScrollExtent;
    final target = estimatedOffset.clamp(0.0, maxOffset);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _showMessageOptions(BuildContext ctx, UiMessage m, bool isPinned) async {
    final renderBox = ctx.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenH = MediaQuery.of(ctx).size.height;
    final screenW = MediaQuery.of(ctx).size.width;
    final menuW = 200.0;
    final centerX = position.dx + size.width / 2;
    final menuY = position.dy < screenH / 2 ? position.dy + size.height : position.dy - 200;

    await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromSize(
        Rect.fromLTWH((centerX - menuW / 2).clamp(10.0, screenW - menuW), menuY.clamp(10.0, screenH - 200), menuW, 200),
        Size(screenW, screenH),
      ),
      items: [
        if (m.text.isNotEmpty || m.images.isNotEmpty)
          PopupMenuItem<String>(
            value: 'pin',
            child: Row(
              children: [
                Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined, size: 20),
                const SizedBox(width: 12),
                Text(isPinned ? 'Открепить' : 'Закрепить'),
              ],
            ),
          ),
        if (m.text.isNotEmpty)
          const PopupMenuItem<String>(
            value: 'copy',
            child: Row(children: [Icon(Icons.copy, size: 20), SizedBox(width: 12), Text('Копировать')]),
          ),
        const PopupMenuItem<String>(
          value: 'reply',
          child: Row(children: [Icon(Icons.reply, size: 20), SizedBox(width: 12), Text('Ответить')]),
        ),
      ],
    ).then((String? value) {
      if (value == 'pin') {
        if (isPinned) {
          _pinStore.unpin(widget.chatRef, m.key);
        } else {
          _pinStore.pin(PinnedMessage(
            chatRef: widget.chatRef,
            key: m.key,
            text: m.text,
            imageFilePath: m.images.isNotEmpty ? m.images.first?.filePath : null,
            timeStr: m.timeStr,
            pinnedAt: DateTime.now(),
          ));
        }
        setState(() {});
      } else if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: m.text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопировано')));
        }
      } else if (value == 'reply') {
        _msgController.text = '> ${m.text.split('\n').first} \n';
        _msgController.selection = TextSelection.fromPosition(
          TextPosition(offset: _msgController.text.length),
        );
      }
    });
  }

  Future<void> _autoReceiveImages(List<UiMessage> parsed) async {
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
        if (img.fileSize != null && img.fileSize! > maxAutoReceiveImageSize) continue;
        _autoRequestedFiles.add(fileId);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final ok = await service.receiveFile(fileId, approvedRelays: true);
        if (ok) anyAccepted = true;
      }
    }
    if (anyAccepted && mounted) await _loadMessages();
  }

  Future<void> _requestFullImage(UiImage image) async {
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
    await service.receiveFile(image.fileId!, approvedRelays: true, encrypt: true);
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
    final isDark = theme.brightness == Brightness.dark;
    final displayItems = _buildDisplayItems(_messages);

    final chatBackground = isDark ? const Color(0xFF0E0E0E) : theme.colorScheme.surface;
    final headerBg = isDark ? const Color(0xFF1C1C1D) : theme.colorScheme.surface;
    final inputBg = isDark ? const Color(0xFF1C1C1D) : theme.colorScheme.surfaceContainerHighest;
    final textPrimary = isDark ? const Color(0xFFFFFFFF) : theme.colorScheme.onSurface;
    final textSecondary = isDark ? const Color(0xFF8E8E93) : theme.colorScheme.outline;

    return Scaffold(
      backgroundColor: chatBackground,
      appBar: AppBar(
        backgroundColor: headerBg,
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: textPrimary), onPressed: () => Navigator.of(context).pop()),
        title: Text(
          widget.chatName,
          style: TextStyle(color: textPrimary, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.4),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: loc.translate('hd_download'),
            icon: Icon(_enableFileReceive ? Icons.cloud_download : Icons.cloud_off, color: textSecondary),
            onPressed: () async {
              final enabled = await showModalBottomSheet<bool>(
                context: context,
                builder: (ctx) {
                  return SafeArea(
                    child: ListTile(
                      leading: Icon(_enableFileReceive ? Icons.cloud_download : Icons.cloud_off),
                      title: Text(loc.translate('hd_download_tooltip')),
                      subtitle: Text(loc.translate('hd_download_warning')),
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
      ),
      body: Column(
        children: [
          if (_audioNowPlaying != null)
            AudioMiniPlayer(player: _audioPlayer, title: _audioNowPlaying!.title),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(child: Text(loc.translate('no_messages_yet'), style: TextStyle(color: textSecondary)))
                    : Column(
                        children: [
                          if (_pinStore.getPinCount(widget.chatRef) > 0)
                            PinnedBar(
                              pinned: _pinStore.getPinned(widget.chatRef),
                              onPinTap: (pm) => _scrollToMessage(pm.key),
                              onUnpin: (pm) { _pinStore.unpin(widget.chatRef, pm.key); setState(() {}); },
                            ),
                          Expanded(
                            child: ListView.builder(
                              controller: _scrollController,
                              reverse: true,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              itemCount: displayItems.length,
                              itemBuilder: (context, index) => displayItems[index],
                            ),
                          ),
                        ],
                      ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              decoration: BoxDecoration(
                color: inputBg,
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0xFF38383A).withOpacity(0.5) : theme.colorScheme.outline.withOpacity(0.15),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(onPressed: _sendingMedia ? null : _openAttachMenu, icon: Icon(Icons.attach_file, color: textSecondary)),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: TextField(
                        controller: _msgController,
                        style: TextStyle(color: textPrimary),
                        decoration: InputDecoration(
                          hintText: loc.translate('message_hint'),
                          hintStyle: TextStyle(color: textSecondary),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        maxLines: 4,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  IconButton(onPressed: _sendingMedia ? null : _openStickerPicker, icon: Icon(Icons.emoji_emotions_outlined, color: textSecondary)),
                  const SizedBox(width: 4),
                  ValueListenableBuilder(
                    valueListenable: _msgController,
                    builder: (context, value, child) {
                      final hasText = value.text.trim().isNotEmpty;
                      return IconButton(
                        onPressed: hasText && !_sending ? _sendMessage : _sendingMedia ? null : _openCircleRecorder,
                        icon: _sending
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(hasText ? Icons.send : Icons.mic, color: hasText ? theme.colorScheme.primary : textSecondary),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<PreviewPayload> _generateVideoThumb(String path) async {
    // Заглушка — реальная генерация в tanglex_service
    return PreviewPayload(bytes: Uint8List(0), mime: 'image/jpeg');
  }

  Future<int> _getVideoDuration(String path) async {
    return 0;
  }

  Future<PreviewPayload> _generateStickerPreview(String path) async {
    // Заглушка — реальная генерация в tanglex_service
    return PreviewPayload(bytes: Uint8List(0), mime: 'image/jpeg');
  }
}
