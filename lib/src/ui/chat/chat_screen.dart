import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../main.dart';
import '../../data/pin_store.dart';
import '../../localization/app_localizations.dart';
import '../../service/tanglex_service.dart' show TanglexService, ImagePayload;
import '../../stickers/sticker_store.dart' show StickerStore, StickerPack, StickerItem;
import 'chat_widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_player_holder.dart';

class _ChatHeader extends StatelessWidget {
  final String title;
  final String chatType;
  final Uint8List? avatarImage;
  final Color textPrimary;
  final Color textSecondary;

  const _ChatHeader({
    required this.title,
    required this.chatType,
    required this.avatarImage,
    required this.textPrimary,
    required this.textSecondary,
  });

  String _subtitle() {
    if (chatType == 'group') return 'Группа';
    if (chatType == 'contact') return 'Контакт';
    return 'Чат';
  }

  String _initials() {
    final parts = title.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      final runes = parts.first.runes.toList();
      final take = runes.take(2).toList();
      return String.fromCharCodes(take).toUpperCase();
    }
    final a = parts[0].runes.isEmpty ? '' : String.fromCharCodes([parts[0].runes.first]);
    final b = parts[1].runes.isEmpty ? '' : String.fromCharCodes([parts[1].runes.first]);
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 4),
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFF2A2A2A),
          backgroundImage: avatarImage != null ? MemoryImage(avatarImage!) : null,
          child: avatarImage == null
              ? Text(
                  _initials(),
                  style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 12),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _subtitle(),
                style: TextStyle(color: textSecondary, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  final String chatRef;
  final String chatName;
  final Uint8List? avatarImage;
  final String chatType;

  const ChatScreen({
    super.key,
    required this.chatRef,
    required this.chatName,
    this.avatarImage,
    required this.chatType,
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
  String? _filesDir;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  Timer? _refreshDebounce;
  final AudioPlayer _audioPlayer = AudioPlayerHolder.player;
  AudioNowPlaying? _audioNowPlaying;
  StreamSubscription<PlayerState>? _audioStateSub;
  final StickerStore _stickerStore = StickerStore.instance;
  final PinStore _pinStore = PinStore.instance;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  final Map<String, int> _displayIndexByKey = {};
  UiMessage? _replyTo;
  bool _circleMode = false;
  int _selectedPackIndex = 0;

  @override
  void initState() {
    super.initState();
    _initFilesDir().then((_) => _loadMessages());
    _pinStore.load();
    _eventSub = ref.read(tanglexServiceProvider).eventStream.listen(_handleEvent);
    _audioStateSub = _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed || state.processingState == ProcessingState.idle) {
        if (_audioNowPlaying != null) {
          setState(() => _audioNowPlaying = null);
        }
      }
    });
  }

  Future<void> _initFilesDir() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/files');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _filesDir = dir.path;
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    try {
      setState(() => _loading = true);
      final service = ref.read(tanglexServiceProvider);
      final msgs = await service.getChatMessages(widget.chatRef);
      final parsed = <UiMessage>[];
      for (final raw in msgs) {
        try {
          final ui = parseChatItem(raw, filesBaseDir: _filesDir);
          if (ui != null) parsed.add(ui);
        } catch (e) {
          debugPrint('Error parsing message: $e');
        }
      }
      parsed.sort((a, b) {
        final at = a.time ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.time ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      if (!mounted) return;
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
          quoted: m.quoted,
          itemId: m.itemId,
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
    } catch (e) {
      debugPrint('Error loading messages: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _sending) return;

    _msgController.clear();
    setState(() => _sending = true);

    final pinCommand = RegExp(r'^/pin\s+');
    final shortPin = RegExp(r'^/p\s+');
    final shouldPin = pinCommand.hasMatch(text) || shortPin.hasMatch(text);
    String actualText = shouldPin
        ? text.replaceFirst(pinCommand, '').replaceFirst(shortPin, '')
        : text;
    final quotedItemId = _replyTo?.itemId;

    final service = ref.read(tanglexServiceProvider);
    final success = await service.sendMessage(widget.chatRef, actualText, quotedItemId: quotedItemId);

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

    setState(() {
      _sending = false;
      _replyTo = null;
    });
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
    final ok = await service.sendImages(widget.chatRef, payload, quotedItemId: _replyTo?.itemId);
    if (ok) {
      await _loadMessages();
      if (mounted) setState(() => _replyTo = null);
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
    final service = ref.read(tanglexServiceProvider);
    final thumb = await _generateVideoThumb(file.path);
    final duration = await _getVideoDuration(file.path);
    final resultSend = await service.sendVideo(
      chatRef: widget.chatRef,
      filePath: file.path,
      previewBytes: thumb.bytes,
      durationSec: duration,
      isCircle: false,
      quotedItemId: _replyTo?.itemId,
    );
    if (resultSend.ok) {
      await _loadMessages();
      if (mounted) setState(() => _replyTo = null);
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
    final stablePath = await _maybePersistPickedFile(path, audioOnly: audioOnly);
    final resultSend = await service.sendFile(
      chatRef: widget.chatRef,
      filePath: stablePath,
      text: '',
      quotedItemId: _replyTo?.itemId,
    );
    if (resultSend.ok) {
      await _loadMessages();
      if (mounted) setState(() => _replyTo = null);
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

  Future<String> _maybePersistPickedFile(String path, {required bool audioOnly}) async {
    final shouldPersist = audioOnly || _isAudioPath(path);
    if (!shouldPersist) return path;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/media_cache');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ext = _fileExt(path);
      final target = File('${dir.path}/file_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(path).copy(target.path);
      return target.path;
    } catch (_) {
      return path;
    }
  }

  bool _isAudioPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.opus') ||
        lower.endsWith('.flac');
  }

  String _fileExt(String path) {
    final idx = path.lastIndexOf('.');
    if (idx == -1) return '';
    return path.substring(idx);
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
    if (!File(audio.filePath!).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Аудиофайл недоступен')),
        );
      }
      return;
    }
    try {
      final isSame = _audioNowPlaying?.filePath == audio.filePath;
      if (!isSame) {
        await _audioPlayer.setFilePath(audio.filePath!);
        await _audioPlayer.play();
      } else {
        if (_audioPlayer.playing) {
          await _audioPlayer.pause();
        } else {
          await _audioPlayer.play();
        }
      }
      setState(() {
        _audioNowPlaying = AudioNowPlaying(filePath: audio.filePath!, title: audio.title);
      });
    } catch (_) {}
  }

  Future<void> _stopAudio() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    if (mounted) {
      setState(() => _audioNowPlaying = null);
    }
  }

  void _openMedia(List<UiImage> images, int index) {
    final img = images[index];
    if (img.isVideo && !img.isCircle) {
      if (img.filePath == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Файл ещё не загружен')));
        return;
      }
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

  Future<void> _requestAudioFile(AudioItem audio) async {
    final fileId = audio.fileId;
    if (fileId == null) return;
    final service = ref.read(tanglexServiceProvider);
    try {
      final ok = await service.receiveFile(
        fileId,
        approvedRelays: true,
        encrypt: false,
        filePath: _filesDir,
      );
      if (ok && mounted) await _loadMessages();
    } catch (e) {
      debugPrint('Error requesting audio file: $e');
    }
  }

  Future<void> _requestFile(UiMessage message) async {
    final fileId = message.fileId;
    if (fileId == null) return;
    if (_filesDir == null) return;
    final service = ref.read(tanglexServiceProvider);
    try {
      final ok = await service.receiveFile(
        fileId,
        approvedRelays: true,
        encrypt: false,
        filePath: _filesDir,
      );
      if (ok && mounted) await _loadMessages();
    } catch (e) {
      debugPrint('Error requesting file: $e');
    }
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
      quotedItemId: _replyTo?.itemId,
    );
    if (resultSend.ok) {
      await _loadMessages();
      if (mounted) setState(() => _replyTo = null);
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

  List<_DisplayEntry> _buildDisplayEntries(List<UiMessage> messages) {
    _displayIndexByKey.clear();
    final entries = <_DisplayEntry>[];
    DateTime? lastDate;
    int i = 0;
    while (i < messages.length) {
      final m = messages[i];

      if (m.time != null) {
        final msgDate = DateTime(m.time!.year, m.time!.month, m.time!.day);
        if (lastDate == null || msgDate != lastDate) {
          entries.add(_DisplayEntry.date(m.time!));
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
        final entryIndex = entries.length;
        for (final g in group) {
          _displayIndexByKey[g.key] = entryIndex;
        }
        entries.add(_DisplayEntry.group(
          UiMessage(
            key: 'group_${m.key}',
            text: m.text,
            fromMe: m.fromMe,
            timeStr: m.timeStr,
            status: m.status,
            isSystem: false,
            images: allImages,
            time: m.time,
          ),
        ));
        i = j;
        continue;
      }
      if (m.isSystem) {
        entries.add(_DisplayEntry.system(m));
      } else {
        _displayIndexByKey[m.key] = entries.length;
        entries.add(_DisplayEntry.message(m));
      }
      i++;
    }
    return entries;
  }

  Widget _buildMessageBubble(UiMessage m) {
    final isPinned = _pinStore.isPinned(widget.chatRef, m.key);
    return MessageBubble(
      message: m,
      onDownloadImage: _requestFullImage,
      onOpenMedia: _openMedia,
      onPlayAudio: _playAudio,
      onDownloadAudio: _requestAudioFile,
      onDownloadFile: _requestFile,
      isPinned: isPinned,
      audioPlayer: _audioPlayer,
      nowPlaying: _audioNowPlaying,
      onLongPress: (d, ctx) => _showMessageOptions(ctx, d.globalPosition, m, isPinned),
      onSwipeReply: () {
        if (m.itemId == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ответ недоступен')));
          return;
        }
        setState(() => _replyTo = m);
      },
    );
  }

  Future<void> _scrollToMessage(String msgKey) async {
    final idx = _displayIndexByKey[msgKey];
    debugPrint('PIN_SCROLL key=$msgKey index=$idx listLen=${_displayIndexByKey.length}');
    if (idx == null) {
      debugPrint('PIN_SCROLL: index not found for key=$msgKey');
      return;
    }
    if (!_itemScrollController.isAttached) {
      debugPrint('PIN_SCROLL: controller not attached');
      return;
    }
    await _itemScrollController.scrollTo(
      index: idx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.2,
    );
  }

  bool _isMessageVisible(String msgKey, Iterable<ItemPosition> positions) {
    final idx = _displayIndexByKey[msgKey];
    if (idx == null) return false;
    for (final p in positions) {
      if (p.index == idx && p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1) {
        return true;
      }
    }
    return false;
  }

  Future<void> _showMessageOptions(BuildContext ctx, Offset tapPosition, UiMessage m, bool isPinned) async {
    final screenH = MediaQuery.of(ctx).size.height;
    final screenW = MediaQuery.of(ctx).size.width;
    final menuW = 210.0;
    final centerX = tapPosition.dx;
    final items = <PopupMenuEntry<String>>[];
    if (m.text.isNotEmpty || m.images.isNotEmpty) {
      items.add(
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
      );
    }
    if (m.text.isNotEmpty) {
      items.add(
        const PopupMenuItem<String>(
          value: 'copy',
          child: Row(children: [Icon(Icons.copy, size: 20), SizedBox(width: 12), Text('Копировать')]),
        ),
      );
    }
    items.add(
      const PopupMenuItem<String>(
        value: 'reply',
        child: Row(children: [Icon(Icons.reply, size: 20), SizedBox(width: 12), Text('Ответить')]),
      ),
    );
    final menuH = items.length * 48.0 + 8.0;
    final menuY = tapPosition.dy < screenH / 2 ? tapPosition.dy + 8 : tapPosition.dy - menuH - 8;

    await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromSize(
        Rect.fromLTWH((centerX - menuW / 2).clamp(10.0, screenW - menuW), menuY.clamp(10.0, screenH - menuH), menuW, menuH),
        Size(screenW, screenH),
      ),
      color: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF1E232A) : const Color(0xFFFFFFFF),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: items,
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
        if (m.itemId == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ответ недоступен')));
          return;
        }
        setState(() => _replyTo = m);
      }
    });
  }

  Future<void> _autoReceiveImages(List<UiMessage> parsed) async {
    if (_filesDir == null) return;
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
        final ok = await service.receiveFile(
          fileId,
          approvedRelays: true,
          encrypt: false,
          filePath: _filesDir,
        );
        if (ok) anyAccepted = true;
      }
    }
    if (anyAccepted && mounted) await _loadMessages();
  }

  Future<void> _requestFullImage(UiImage image) async {
    final loc = AppLocalizations.of(context);
    if (image.fileId == null) return;
    if (image.fileStatusType != 'rcvInvitation') return;
    final service = ref.read(tanglexServiceProvider);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final ok = await service.receiveFile(
        image.fileId!,
        approvedRelays: true,
        encrypt: false,
        filePath: _filesDir,
      );
      if (ok && mounted) {
        await _loadMessages();
      }
    } catch (e) {
      debugPrint('Error requesting file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка загрузки файла')),
        );
      }
    }
  }

  @override
  void dispose() {
    _msgController.dispose();
    _audioStateSub?.cancel();
    _eventSub?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final displayEntries = _buildDisplayEntries(_messages);

    final chatBackground = const Color(0xFF000000);
    final headerBg = const Color(0xFF111111);
    final inputBg = const Color(0xFF111111);
    final textPrimary = const Color(0xFFE8E8E8);
    final textSecondary = const Color(0xFF808080);

    return Scaffold(
      backgroundColor: chatBackground,
      appBar: AppBar(
        backgroundColor: headerBg,
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: textPrimary), onPressed: () => Navigator.of(context).pop()),
        titleSpacing: 0,
        title: _ChatHeader(
          title: widget.chatName,
          chatType: widget.chatType,
          avatarImage: widget.avatarImage,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
        ),
      ),
      body: SelectionArea(
        child: Column(
        children: [
          if (_audioNowPlaying != null)
            AudioMiniPlayer(
              player: _audioPlayer,
              title: _audioNowPlaying!.title,
              onClose: _stopAudio,
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(child: Text(loc.translate('no_messages_yet'), style: TextStyle(color: textSecondary)))
                    : Column(
                        children: [
                          if (_pinStore.getPinCount(widget.chatRef) > 0)
                            ValueListenableBuilder<Iterable<ItemPosition>>(
                              valueListenable: _itemPositionsListener.itemPositions,
                              builder: (context, positions, _) {
                                return PinnedBar(
                                  pinned: _pinStore.getPinned(widget.chatRef),
                                  onPinTap: (pm) => _scrollToMessage(pm.key),
                                  onUnpin: (pm) { _pinStore.unpin(widget.chatRef, pm.key); setState(() {}); },
                                  isPinVisible: (pm) => _isMessageVisible(pm.key, positions),
                                );
                              },
                            ),
                          Expanded(
                            child: ScrollablePositionedList.builder(
                              itemScrollController: _itemScrollController,
                              itemPositionsListener: _itemPositionsListener,
                              reverse: true,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              itemCount: displayEntries.length,
                              itemBuilder: (context, index) {
                                final entry = displayEntries[index];
                                switch (entry.type) {
                                  case _DisplayEntryType.date:
                                    return DateDivider(date: entry.date!);
                                  case _DisplayEntryType.system:
                                    return SystemBubble(text: entry.message!.text);
                                  case _DisplayEntryType.group:
                                  case _DisplayEntryType.message:
                                    return _buildMessageBubble(entry.message!);
                                }
                              },
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
                border: const Border(
                  top: BorderSide(
                    color: Color(0xFF333333),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyTo != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF303030),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF3A3A3A),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 40,
                            margin: const EdgeInsets.only(left: 0, right: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF5A9CF5),
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(11),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _replyTo!.fromMe ? 'Вы' : widget.chatName,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF5A9CF5),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _replyTo!.text.split('\n').first,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _replyTo = null),
                            icon: Icon(Icons.close, size: 18, color: textSecondary),
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: _sendingMedia ? null : _openStickerPicker,
                        icon: Icon(Icons.emoji_emotions_outlined, color: textSecondary),
                      ),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: TextField(
                            controller: _msgController,
                            style: TextStyle(color: textPrimary),
                            decoration: InputDecoration(
                              hintText: loc.translate('message_hint'),
                              hintStyle: const TextStyle(color: Color(0xFF606060)),
                              filled: true,
                              fillColor: const Color(0xFF222222),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            maxLines: 4,
                            minLines: 1,
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _sendingMedia ? null : _sendImages,
                        icon: Icon(Icons.photo_camera_outlined, color: textSecondary),
                      ),
                      IconButton(
                        onPressed: _sendingMedia ? null : _openAttachMenu,
                        icon: Icon(Icons.attach_file, color: textSecondary),
                      ),
                      ValueListenableBuilder(
                        valueListenable: _msgController,
                        builder: (context, value, child) {
                          final hasText = value.text.trim().isNotEmpty;
                          if (hasText) {
                            return IconButton(
                              onPressed: _sending ? null : _sendMessage,
                              icon: _sending
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Icon(Icons.send, color: theme.colorScheme.primary),
                            );
                          }
                          return GestureDetector(
                            onTap: () => setState(() => _circleMode = !_circleMode),
                            onLongPress: _sendingMedia
                                ? null
                                : () {
                                    if (_circleMode) {
                                      _openCircleRecorder();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Голосовые пока недоступны')),
                                      );
                                    }
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Icon(
                                _circleMode ? Icons.radio_button_checked : Icons.mic,
                                color: textSecondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

enum _DisplayEntryType { date, system, message, group }

class _DisplayEntry {
  final _DisplayEntryType type;
  final UiMessage? message;
  final DateTime? date;

  const _DisplayEntry._(this.type, {this.message, this.date});

  factory _DisplayEntry.date(DateTime date) => _DisplayEntry._(_DisplayEntryType.date, date: date);
  factory _DisplayEntry.system(UiMessage message) => _DisplayEntry._(_DisplayEntryType.system, message: message);
  factory _DisplayEntry.message(UiMessage message) => _DisplayEntry._(_DisplayEntryType.message, message: message);
  factory _DisplayEntry.group(UiMessage message) => _DisplayEntry._(_DisplayEntryType.group, message: message);
}
