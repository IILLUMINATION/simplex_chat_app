// Tanglex chat screen — переписан с нуля в build-mode сессии.
//
// Цели реврайта:
//   * Чистая разделённая структура (раньше был монолит на 1.8k строк
//     с перемешанными слоями загрузки/состояния/UI/жестов).
//   * Telegram-подобный dark UX: тонкие пузыри, аватары в шапке,
//     reply-preview, attach-sheet, sticker-sheet.
//   * Все async-пути аккуратно проверяют mounted перед setState/SnackBar.
//   * Кружки и аудио-воспроизведение лениво поднимают свои контроллеры,
//     не дёргают audio focus впустую (см. media_widgets.dart).
//   * Никаких хардкодных русских строк в snackbar/menu — всё через
//     AppLocalizations.
//
// Внутренние виджеты MessageBubble / MediaGrid / StickerView / VideoCircle /
// AudioBubble / FileAttachment / SwipeReplyWrapper остаются прежние —
// они уже выглядят прилично и протестированы.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vthumb;

import '../../../main.dart';
import '../../data/pin_store.dart';
import '../../localization/app_localizations.dart';
import '../../service/tanglex_service.dart'
    show ImagePayload, SendMessageResult;
import '../../stickers/sticker_store.dart'
    show StickerStore, StickerPack, StickerItem;
import 'audio_player_holder.dart';
import 'chat_widgets.dart';
import 'models/chat_message_models.dart';
import 'utils/chat_message_parser.dart'
    show
        compressPreview,
        makePreview,
        parseChatItem,
        prepareStickerPreview,
        slugify;

// =============================================================================
// THEME
// =============================================================================

/// Палитра экрана чата. Вынесена в одно место чтобы потом легко свапнуть
/// или поднять в общий ThemeData.
class _ChatTheme {
  static const Color bg = Color(0xFF0E0E10);
  static const Color appBarBg = Color(0xFF15161A);
  static const Color composeBg = Color(0xFF15161A);
  static const Color textPrimary = Color(0xFFE9E9EC);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color accent = Color(0xFF5A9CF5);
  static const Color avatarBg = Color(0xFF2A2A2A);
  static const Color divider = Color(0xFF2C2C2E);
  static const Color quotedBar = Color(0xFF5A9CF5);
  static const Color dateChip = Color(0x88202024);
}

// =============================================================================
// GLOBAL HELPERS
// =============================================================================

/// Не сбрасывается между экранами — путь к директории файлов задаёт
/// SimpleX core один раз через `/_files_folder` (см. TanglexService).
String? _cachedFilesDir;

/// Парсинг чат-ивентов в отдельном изоляте, чтобы не лагал UI.
List<UiMessage> _parseMessagesIsolate(Map<String, dynamic> params) {
  final msgs = params['msgs'] as List;
  final filesBaseDir = params['filesBaseDir'] as String?;
  final parsed = <UiMessage>[];
  for (final raw in msgs) {
    try {
      final ui = parseChatItem(
        Map<String, dynamic>.from(raw as Map),
        filesBaseDir: filesBaseDir,
      );
      if (ui != null) parsed.add(ui);
    } catch (_) {
      // skip malformed
    }
  }
  return parsed;
}

// =============================================================================
// PUBLIC ENTRY POINT
// =============================================================================

class ChatScreen extends ConsumerStatefulWidget {
  final String chatRef;
  final String chatName;
  final Uint8List? avatarImage;
  final String chatType;

  /// Поднимается из ChatPreview.isMessagingReady — пока соединение
  /// не готово, отключаем ComposeBar.
  final bool initialMessagingReady;

  const ChatScreen({
    super.key,
    required this.chatRef,
    required this.chatName,
    this.avatarImage,
    required this.chatType,
    this.initialMessagingReady = true,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  // ---- text input
  final TextEditingController _msgController = TextEditingController();
  final FocusNode _msgFocus = FocusNode();
  bool _composeHasText = false;

  // ---- data
  List<UiMessage> _messages = const [];
  List<_DisplayEntry> _displayEntries = const [];
  final Map<String, int> _displayIndexByKey = {};
  bool _loadingInitial = true;
  bool _messagingReady = true;
  bool _sending = false;
  bool _sendingMedia = false;

  // ---- attached file requests dedup
  final Set<int> _autoRequestedFiles = <int>{};

  // ---- audio playback
  final AudioPlayer _audioPlayer = AudioPlayerHolder.player;
  AudioNowPlaying? _audioNowPlaying;
  StreamSubscription<PlayerState>? _audioStateSub;

  // ---- stores
  final StickerStore _stickerStore = StickerStore.instance;
  final PinStore _pinStore = PinStore.instance;
  int _selectedPackIndex = 0;

  // ---- scrolling
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  bool _showJumpToBottom = false;

  // ---- events
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  Timer? _refreshDebounce;

  // ---- reply state
  UiMessage? _replyTo;

  // =========================================================================
  // LIFECYCLE
  // =========================================================================

  @override
  void initState() {
    super.initState();
    _messagingReady =
        widget.chatType != 'contact' || widget.initialMessagingReady;
    _msgController.addListener(_onComposeTextChanged);
    _positionsListener.itemPositions.addListener(_onScrollPositionsChanged);

    // Открываем экран мгновенно — данные грузим после первого кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initFilesDir().then((_) {
        if (mounted) _loadMessages(initial: true);
      });
    });

    unawaited(_pinStore.load());
    unawaited(_stickerStore.ensureLoaded());

    _eventSub = ref
        .read(tanglexServiceProvider)
        .eventStream
        .listen(_handleEvent);

    _audioStateSub = _audioPlayer.playerStateStream.listen(_handleAudioState);
  }

  @override
  void dispose() {
    _msgController.removeListener(_onComposeTextChanged);
    _msgController.dispose();
    _msgFocus.dispose();
    _positionsListener.itemPositions.removeListener(_onScrollPositionsChanged);
    _refreshDebounce?.cancel();
    _eventSub?.cancel();
    _audioStateSub?.cancel();
    super.dispose();
  }

  void _onComposeTextChanged() {
    final hasText = _msgController.text.trim().isNotEmpty;
    if (hasText != _composeHasText) {
      setState(() => _composeHasText = hasText);
    }
  }

  void _onScrollPositionsChanged() {
    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    // Reverse-scrolled list — bottom = первый элемент.
    final minIndex = positions
        .map((p) => p.index)
        .reduce((a, b) => a < b ? a : b);
    final show = minIndex > 3;
    if (show != _showJumpToBottom) {
      setState(() => _showJumpToBottom = show);
    }
  }

  // =========================================================================
  // DATA LOADING
  // =========================================================================

  Future<void> _initFilesDir() async {
    if (_cachedFilesDir != null) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/files');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cachedFilesDir = dir.path;
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _loadMessages({bool initial = false}) async {
    try {
      if (initial && mounted) {
        setState(() => _loadingInitial = _messages.isEmpty);
      }
      final service = ref.read(tanglexServiceProvider);
      final raw = await service.getChatMessages(widget.chatRef);
      final parsed = await compute(_parseMessagesIsolate, {
        'msgs': raw.map((m) => Map<String, dynamic>.from(m)).toList(),
        'filesBaseDir': _cachedFilesDir,
      });
      // Сортируем по убыванию времени (свежие — в начале).
      parsed.sort((a, b) {
        final at = a.time ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.time ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });

      // /pin sentinel cleanup (как в прошлом клиенте — закрепы локальные).
      final pinPattern = RegExp(r'^/pin\s+');
      final shortPin = RegExp(r'^/p\s+');
      final cleaned = <UiMessage>[];
      for (final m in parsed) {
        if (pinPattern.hasMatch(m.text) || shortPin.hasMatch(m.text)) {
          final actual = m.text
              .replaceFirst(pinPattern, '')
              .replaceFirst(shortPin, '');
          if (!_pinStore.isPinned(widget.chatRef, m.key)) {
            unawaited(
              _pinStore.pin(
                PinnedMessage(
                  chatRef: widget.chatRef,
                  key: m.key,
                  text: actual,
                  imageFilePath: m.images.isNotEmpty
                      ? m.images.first.filePath
                      : null,
                  timeStr: m.timeStr,
                  pinnedAt: DateTime.now(),
                ),
              ),
            );
          }
          cleaned.add(_withText(m, actual));
        } else {
          cleaned.add(m);
        }
      }

      if (!mounted) return;
      setState(() {
        _messages = cleaned;
        _displayEntries = _buildDisplayEntries(cleaned);
        _displayIndexByKey
          ..clear()
          ..addAll({
            for (var i = 0; i < _displayEntries.length; i++)
              if (_displayEntries[i].message != null)
                _displayEntries[i].message!.key: i,
          });
        _loadingInitial = false;
      });

      await _autoReceiveImages(cleaned);
      await _refreshMessagingReadyFlag();
    } catch (e) {
      debugPrint('chat: loadMessages error: $e');
      if (mounted) {
        setState(() => _loadingInitial = false);
      }
    }
  }

  UiMessage _withText(UiMessage m, String newText) => UiMessage(
        key: m.key,
        text: newText,
        fromMe: m.fromMe,
        timeStr: m.timeStr,
        status: m.status,
        isSystem: m.isSystem,
        images: m.images,
        time: m.time,
        itemId: m.itemId,
        quoted: m.quoted,
        audio: m.audio,
        fileName: m.fileName,
        fileSize: m.fileSize,
        filePath: m.filePath,
        fileId: m.fileId,
        fileStatusType: m.fileStatusType,
        transferProgress: m.transferProgress,
        transferTotal: m.transferTotal,
      );

  Future<void> _refreshMessagingReadyFlag() async {
    if (widget.chatType != 'contact') return;
    final service = ref.read(tanglexServiceProvider);
    final ready = await service.getContactMessagingReady(widget.chatRef);
    if (!mounted || ready == null) return;
    if (ready != _messagingReady) {
      setState(() => _messagingReady = ready);
    }
  }

  Future<void> _autoReceiveImages(List<UiMessage> msgs) async {
    final service = ref.read(tanglexServiceProvider);
    for (final m in msgs) {
      for (final img in m.images) {
        if (img.fileId == null) continue;
        if (img.filePath != null && File(img.filePath!).existsSync()) continue;
        if (img.fileStatusType != 'rcvInvitation') continue;
        if (img.fileSize != null && img.fileSize! > 1024 * 1024 * 25) continue;
        if (!_autoRequestedFiles.add(img.fileId!)) continue;
        unawaited(
          service.receiveFile(
            img.fileId!,
            approvedRelays: true,
            encrypt: false,
            filePath: _cachedFilesDir,
          ),
        );
      }
    }
  }

  // =========================================================================
  // EVENTS
  // =========================================================================

  void _handleEvent(Map<String, dynamic> event) {
    final result = event['result'];
    if (result is! Map) return;
    final type = result['type'] as String?;
    if (type == null) return;
    const interesting = {
      'chatItemNew',
      'newChatItems',
      'chatItem',
      'chatItemUpdated',
      'chatItemsDeleted',
      'chatItemsStatusesUpdated',
      'groupChatItemsDeleted',
      'rcvFileSndCancelled',
      'rcvFileComplete',
      'sndFileComplete',
      'rcvFileStart',
      'sndFileStart',
      'rcvFileProgressXFTP',
      'sndFileProgressXFTP',
      'contactSndReady',
    };
    if (interesting.contains(type)) {
      _scheduleRefresh();
    }
    if (type == 'contactSndReady' && widget.chatType == 'contact') {
      _refreshMessagingReadyFlag();
    }
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _loadMessages();
    });
  }

  void _handleAudioState(PlayerState state) {
    if (!mounted) return;
    if (state.processingState == ProcessingState.completed ||
        state.processingState == ProcessingState.idle) {
      if (_audioNowPlaying != null) {
        setState(() => _audioNowPlaying = null);
      }
    }
  }

  // =========================================================================
  // SENDING
  // =========================================================================

  bool get _canCompose => widget.chatType != 'contact' || _messagingReady;

  Future<void> _sendText() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _sending || !_canCompose) return;
    final replyId = _replyTo?.itemId;
    _msgController.clear();
    setState(() => _sending = true);

    // Локальный pin sentinel ("/pin ..." и "/p ...") — поддерживаем как
    // раньше: после успешной отправки берём последнее сообщение и пинним.
    final pinPattern = RegExp(r'^/pin\s+');
    final shortPin = RegExp(r'^/p\s+');
    final isPinCmd = pinPattern.hasMatch(text) || shortPin.hasMatch(text);
    final actualText = isPinCmd
        ? text.replaceFirst(pinPattern, '').replaceFirst(shortPin, '')
        : text;

    final service = ref.read(tanglexServiceProvider);
    final result = await service.sendMessage(
      widget.chatRef,
      actualText,
      quotedItemId: replyId,
    );

    if (!mounted) return;
    if (!result.ok) {
      _msgController.text = text;
      final loc = AppLocalizations.of(context);
      _snack(_labelForSendFailure(loc, result));
    } else {
      await _loadMessages();
      if (isPinCmd && _messages.isNotEmpty) {
        final last = _messages.first;
        unawaited(
          _pinStore.pin(
            PinnedMessage(
              chatRef: widget.chatRef,
              key: last.key,
              text: last.text,
              imageFilePath:
                  last.images.isNotEmpty ? last.images.first.filePath : null,
              timeStr: last.timeStr,
              pinnedAt: DateTime.now(),
            ),
          ),
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _sending = false;
      _replyTo = null;
    });
  }

  String _labelForSendFailure(AppLocalizations loc, SendMessageResult r) {
    switch (r.errorType) {
      case 'contactNotReady':
        return loc.translate('send_error_contact_not_ready');
      case 'contactNotActive':
        return loc.translate('send_error_contact_not_active');
      case 'noResponse':
        return loc.translate('send_error_no_response');
      case 'parseError':
        return loc.translate('send_error_parse');
      default:
        return r.detail ?? loc.translate('send_error_no_response');
    }
  }

  Future<void> _sendImages() async {
    if (_sendingMedia) return;
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 90);
    if (files.isEmpty) return;
    if (!mounted) return;
    setState(() => _sendingMedia = true);
    final service = ref.read(tanglexServiceProvider);
    final payload = <ImagePayload>[];
    for (final f in files) {
      final bytes = await f.readAsBytes();
      final preview = makePreview(bytes);
      payload.add(
        ImagePayload(
          filePath: f.path,
          previewBytes: preview.bytes,
          previewMime: preview.mime,
        ),
      );
    }
    final ok = await service.sendImages(
      widget.chatRef,
      payload,
      quotedItemId: _replyTo?.itemId,
    );
    if (!mounted) return;
    if (ok) {
      await _loadMessages();
    }
    if (!mounted) return;
    setState(() {
      _sendingMedia = false;
      if (ok) _replyTo = null;
    });
  }

  Future<void> _pickAndSendVideo() async {
    if (_sendingMedia) return;
    final picker = ImagePicker();
    final f = await picker.pickVideo(source: ImageSource.gallery);
    if (f == null) return;
    if (!mounted) return;
    setState(() => _sendingMedia = true);
    final service = ref.read(tanglexServiceProvider);
    final thumb = await _generateVideoThumb(f.path);
    final duration = await _getVideoDuration(f.path);
    final res = await service.sendVideo(
      chatRef: widget.chatRef,
      filePath: f.path,
      previewBytes: thumb.bytes,
      durationSec: duration,
      isCircle: false,
      quotedItemId: _replyTo?.itemId,
    );
    if (!mounted) return;
    if (res.ok) {
      await _loadMessages();
    } else {
      final loc = AppLocalizations.of(context);
      _snack(
        res.error == null
            ? loc.translate('failed_send_video')
            : loc
                .translate('failed_send_error')
                .replaceAll('%s', res.error ?? ''),
      );
    }
    if (!mounted) return;
    setState(() {
      _sendingMedia = false;
      if (res.ok) _replyTo = null;
    });
  }

  Future<void> _pickAndSendFile({bool audioOnly = false}) async {
    if (_sendingMedia) return;
    final picked = await FilePicker.platform.pickFiles(
      type: audioOnly ? FileType.audio : FileType.any,
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null) return;
    if (!mounted) return;
    setState(() => _sendingMedia = true);
    final stable = await _persistAudioFile(path, audioOnly: audioOnly);
    final lower = stable.toLowerCase();
    final isStickerFile =
        lower.endsWith('.webp') || lower.endsWith('.webm');
    final tagText = isStickerFile ? '/sticker' : '';
    final service = ref.read(tanglexServiceProvider);
    final res = await service.sendFile(
      chatRef: widget.chatRef,
      filePath: stable,
      text: tagText,
      quotedItemId: _replyTo?.itemId,
    );
    if (!mounted) return;
    if (res.ok) {
      await _loadMessages();
    } else {
      final loc = AppLocalizations.of(context);
      _snack(
        res.error == null
            ? loc.translate('failed_send_file')
            : loc
                .translate('failed_send_error')
                .replaceAll('%s', res.error ?? ''),
      );
    }
    if (!mounted) return;
    setState(() {
      _sendingMedia = false;
      if (res.ok) _replyTo = null;
    });
  }

  Future<String> _persistAudioFile(
    String path, {
    required bool audioOnly,
  }) async {
    final shouldPersist = audioOnly || _isAudioPath(path);
    if (!shouldPersist) return path;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/media_cache');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final ext = _fileExt(path);
      final target = File(
        '${dir.path}/file_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
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

  Future<PreviewPayload> _generateVideoThumb(String path) async {
    try {
      final data = await vthumb.VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: vthumb.ImageFormat.JPEG,
        maxWidth: 480,
        quality: 75,
      );
      if (data != null) {
        return compressPreview(
          PreviewPayload(bytes: data, mime: 'image/jpeg'),
          maxBytes: 45000,
        );
      }
    } catch (_) {}
    return PreviewPayload(bytes: Uint8List(0), mime: 'image/jpeg');
  }

  Future<int> _getVideoDuration(String path) async {
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      return controller.value.duration.inSeconds;
    } catch (_) {
      return 0;
    } finally {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  Future<void> _openCircleRecorder() async {
    if (_sendingMedia) return;
    final loc = AppLocalizations.of(context);
    final result = await Navigator.of(context).push<CircleVideoResult>(
      MaterialPageRoute(
        builder: (_) => const CircleRecorderScreen(),
        fullscreenDialog: true,
      ),
    );
    if (result == null) return;
    if (!mounted) return;
    setState(() => _sendingMedia = true);
    final service = ref.read(tanglexServiceProvider);
    final res = await service.sendVideo(
      chatRef: widget.chatRef,
      filePath: result.filePath,
      previewBytes: result.previewBytes,
      durationSec: result.durationSec,
      isCircle: true,
      quotedItemId: _replyTo?.itemId,
    );
    if (!mounted) return;
    if (res.ok) {
      await _loadMessages();
    } else {
      _snack(
        res.error == null
            ? loc.translate('failed_send_circle')
            : loc
                .translate('failed_send_error')
                .replaceAll('%s', res.error ?? ''),
      );
    }
    if (!mounted) return;
    setState(() {
      _sendingMedia = false;
      if (res.ok) _replyTo = null;
    });
  }

  Future<void> _sendSticker(StickerPack pack, StickerItem sticker) async {
    if (_sendingMedia) return;
    if (!mounted) return;
    setState(() => _sendingMedia = true);
    final service = ref.read(tanglexServiceProvider);
    final preview = await _generateStickerPreview(sticker.filePath);
    final res = await service.sendSticker(
      chatRef: widget.chatRef,
      filePath: sticker.filePath,
      previewBytes: preview.bytes,
      previewMime: preview.mime,
      packId: pack.id,
      stickerId: sticker.id,
    );
    if (!mounted) return;
    if (res.ok) {
      await _loadMessages();
    } else {
      final loc = AppLocalizations.of(context);
      _snack(
        res.error == null
            ? loc.translate('failed_send_sticker')
            : 'Send failed: ${res.error}',
      );
    }
    if (!mounted) return;
    setState(() => _sendingMedia = false);
  }

  Future<PreviewPayload> _generateStickerPreview(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final prepared = prepareStickerPreview(bytes);
      return compressPreview(prepared, maxBytes: 45000);
    } catch (_) {
      return PreviewPayload(bytes: Uint8List(0), mime: 'image/webp');
    }
  }

  // =========================================================================
  // MEDIA / AUDIO HANDLERS
  // =========================================================================

  Future<void> _playAudio(AudioItem audio) async {
    final path = audio.filePath;
    if (path == null) return;
    if (!File(path).existsSync()) {
      if (mounted) {
        _snack(AppLocalizations.of(context).translate('audio_unavailable'));
      }
      return;
    }
    try {
      final isSame = _audioNowPlaying?.filePath == path;
      if (isSame) {
        if (_audioPlayer.playing) {
          await _audioPlayer.pause();
        } else {
          await _audioPlayer.play();
        }
        if (mounted) {
          setState(() {
            _audioNowPlaying = AudioNowPlaying(
              filePath: path,
              title: audio.title,
            );
          });
        }
        return;
      }
      try {
        await _audioPlayer.stop();
      } catch (_) {}
      await _audioPlayer.setFilePath(path);
      if (mounted) {
        setState(() {
          _audioNowPlaying = AudioNowPlaying(
            filePath: path,
            title: audio.title,
          );
        });
      }
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('chat: audio play error: $e');
      if (mounted) {
        _snack(AppLocalizations.of(context).translate('audio_unavailable'));
      }
    }
  }

  Future<void> _requestAudioFile(AudioItem audio) async {
    if (audio.fileId == null) return;
    final service = ref.read(tanglexServiceProvider);
    try {
      await service.receiveFile(
        audio.fileId!,
        approvedRelays: true,
        encrypt: false,
        filePath: _cachedFilesDir,
      );
      await _loadMessages();
    } catch (e) {
      debugPrint('chat: receive audio file error: $e');
    }
  }

  Future<void> _requestFile(UiMessage m) async {
    if (m.fileId == null) return;
    final service = ref.read(tanglexServiceProvider);
    try {
      final ok = await service.receiveFile(
        m.fileId!,
        approvedRelays: true,
        encrypt: false,
        filePath: _cachedFilesDir,
      );
      if (ok && mounted) await _loadMessages();
    } catch (e) {
      debugPrint('chat: receive file error: $e');
      if (mounted) {
        _snack(AppLocalizations.of(context).translate('file_load_error'));
      }
    }
  }

  Future<void> _requestImage(UiImage img) async {
    if (img.fileId == null) return;
    final service = ref.read(tanglexServiceProvider);
    try {
      final ok = await service.receiveFile(
        img.fileId!,
        approvedRelays: true,
        encrypt: false,
        filePath: _cachedFilesDir,
      );
      if (ok && mounted) await _loadMessages();
    } catch (e) {
      debugPrint('chat: receive image error: $e');
    }
  }

  void _openMedia(List<UiImage> images, int index) {
    final img = images[index];
    if (img.isVideo && !img.isCircle) {
      if (img.filePath == null) {
        _snack(AppLocalizations.of(context).translate('file_not_loaded'));
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
    if (!img.isVideo && !img.isCircle && img.filePath != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GalleryView(
            images: images,
            initial: index,
          ),
          fullscreenDialog: true,
        ),
      );
    }
  }

  // =========================================================================
  // CONTEXT MENU / REPLY / PIN
  // =========================================================================

  Future<void> _showMessageOptions(
    BuildContext ctx,
    Offset pos,
    UiMessage m,
    bool isPinned,
  ) async {
    final loc = AppLocalizations.of(ctx);
    final size = MediaQuery.of(ctx).size;
    final entries = <PopupMenuEntry<String>>[
      if (m.text.isNotEmpty || m.images.isNotEmpty)
        PopupMenuItem<String>(
          value: 'pin',
          child: _menuItem(
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            label: loc.translate(isPinned ? 'message_unpin' : 'message_pin'),
          ),
        ),
      if (m.text.isNotEmpty)
        PopupMenuItem<String>(
          value: 'copy',
          child: _menuItem(
            icon: Icons.copy,
            label: loc.translate('message_copy'),
          ),
        ),
      PopupMenuItem<String>(
        value: 'reply',
        child: _menuItem(
          icon: Icons.reply,
          label: loc.translate('message_reply'),
        ),
      ),
    ];
    const menuW = 220.0;
    final menuH = entries.length * 48.0 + 12.0;
    final menuX = (pos.dx - menuW / 2).clamp(10.0, size.width - menuW - 10.0);
    final menuY = pos.dy < size.height / 2
        ? pos.dy + 8
        : (pos.dy - menuH - 8).clamp(40.0, size.height - menuH - 40.0);

    final selected = await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromSize(
        Rect.fromLTWH(menuX, menuY, menuW, menuH),
        size,
      ),
      color: const Color(0xFF1E232A),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: entries,
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'pin':
        if (isPinned) {
          await _pinStore.unpin(widget.chatRef, m.key);
        } else {
          await _pinStore.pin(
            PinnedMessage(
              chatRef: widget.chatRef,
              key: m.key,
              text: m.text,
              imageFilePath:
                  m.images.isNotEmpty ? m.images.first.filePath : null,
              timeStr: m.timeStr,
              pinnedAt: DateTime.now(),
            ),
          );
        }
        if (mounted) setState(() {});
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.text));
        if (mounted) _snack(loc.translate('message_copied'));
        break;
      case 'reply':
        _setReply(m);
        break;
    }
  }

  Widget _menuItem({required IconData icon, required String label}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _ChatTheme.textPrimary),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: _ChatTheme.textPrimary)),
      ],
    );
  }

  void _setReply(UiMessage m) {
    if (m.itemId == null) {
      _snack(AppLocalizations.of(context).translate('reply_unavailable'));
      return;
    }
    setState(() => _replyTo = m);
    _msgFocus.requestFocus();
  }

  // =========================================================================
  // DISPLAY ENTRIES (date separators + messages)
  // =========================================================================

  List<_DisplayEntry> _buildDisplayEntries(List<UiMessage> msgs) {
    // msgs are sorted newest-first; reverse list rendering keeps that order.
    final out = <_DisplayEntry>[];
    String? lastDate;
    for (final m in msgs) {
      out.add(_DisplayEntry.message(m));
      final d = m.time;
      if (d != null) {
        final key = '${d.year}-${d.month}-${d.day}';
        if (lastDate != key) {
          out.add(_DisplayEntry.date(d));
          lastDate = key;
        }
      }
    }
    return out;
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: _ChatTheme.bg,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(loc),
      body: Column(
        children: [
          Expanded(child: _buildBody(loc)),
          if (_replyTo != null) _buildReplyPreview(loc),
          _buildComposeBar(loc),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations loc) {
    return AppBar(
      backgroundColor: _ChatTheme.appBarBg,
      elevation: 0,
      titleSpacing: 0,
      iconTheme: const IconThemeData(color: _ChatTheme.textPrimary),
      title: Row(
        children: [
          _Avatar(name: widget.chatName, image: widget.avatarImage, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.chatName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ChatTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  _subtitleText(loc),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ChatTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _openChatMenu(loc),
          tooltip: 'More',
        ),
      ],
    );
  }

  String _subtitleText(AppLocalizations loc) {
    if (widget.chatType == 'group') return loc.translate('chat_type_group');
    if (widget.chatType == 'contact') {
      return _messagingReady
          ? loc.translate('chat_type_contact')
          : loc.translate('connecting_secure');
    }
    return loc.translate('chat_type_chat');
  }

  void _openChatMenu(AppLocalizations loc) {
    final pinned = _pinStore.getPinned(widget.chatRef);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _ChatTheme.appBarBg,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pinned.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.push_pin, color: _ChatTheme.accent),
                title: Text(
                  '${loc.translate('message_pin')} (${pinned.length})',
                  style: const TextStyle(color: _ChatTheme.textPrimary),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showPinnedList(loc, pinned);
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.refresh,
                color: _ChatTheme.textSecondary,
              ),
              title: Text(
                loc.translate('refresh'),
                style: const TextStyle(color: _ChatTheme.textPrimary),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _loadMessages();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPinnedList(AppLocalizations loc, List<PinnedMessage> pinned) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _ChatTheme.appBarBg,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => ListView.separated(
          controller: scrollCtrl,
          itemCount: pinned.length,
          separatorBuilder: (_, __) =>
              const Divider(color: _ChatTheme.divider, height: 1),
          itemBuilder: (_, i) {
            final p = pinned[i];
            return ListTile(
              leading: const Icon(
                Icons.push_pin,
                color: _ChatTheme.accent,
                size: 20,
              ),
              title: Text(
                p.text.isEmpty ? '(media)' : p.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _ChatTheme.textPrimary),
              ),
              subtitle: Text(
                p.timeStr,
                style: const TextStyle(color: _ChatTheme.textSecondary),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, color: _ChatTheme.textSecondary),
                onPressed: () async {
                  await _pinStore.unpin(widget.chatRef, p.key);
                  if (mounted) {
                    Navigator.of(ctx).pop();
                    setState(() {});
                  }
                },
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _scrollToKey(p.key);
              },
            );
          },
        ),
      ),
    );
  }

  void _scrollToKey(String key) {
    final idx = _displayIndexByKey[key];
    if (idx == null || !_scrollController.isAttached) return;
    _scrollController.scrollTo(
      index: idx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
      alignment: 0.2,
    );
  }

  void _scrollToItemId(int itemId) {
    final idx = _messages.indexWhere((m) => m.itemId == itemId);
    if (idx < 0) {
      _snack(AppLocalizations.of(context).translate('message_not_found'));
      return;
    }
    _scrollToKey(_messages[idx].key);
  }

  Widget _buildBody(AppLocalizations loc) {
    if (_loadingInitial) {
      return const Center(
        child: CircularProgressIndicator(color: _ChatTheme.accent),
      );
    }
    if (_displayEntries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            loc.translate('no_messages_yet'),
            style: const TextStyle(color: _ChatTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Stack(
      children: [
        ScrollablePositionedList.builder(
          reverse: true,
          itemCount: _displayEntries.length,
          itemScrollController: _scrollController,
          itemPositionsListener: _positionsListener,
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemBuilder: (context, index) => _buildEntry(_displayEntries[index]),
        ),
        if (_showJumpToBottom)
          Positioned(
            right: 12,
            bottom: 12,
            child: _JumpToBottomButton(
              onTap: () {
                if (_scrollController.isAttached) {
                  _scrollController.scrollTo(
                    index: 0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                  );
                }
              },
            ),
          ),
      ],
    );
  }

  Widget _buildEntry(_DisplayEntry e) {
    if (e.kind == _DisplayKind.date && e.date != null) {
      return _DateChip(date: e.date!);
    }
    final m = e.message!;
    if (m.isSystem) {
      return _SystemBanner(text: m.text);
    }
    final isPinned = _pinStore.isPinned(widget.chatRef, m.key);
    return MessageBubble(
      key: ValueKey(m.key),
      message: m,
      isPinned: isPinned,
      audioPlayer: _audioPlayer,
      nowPlaying: _audioNowPlaying,
      onDownloadImage: _requestImage,
      onOpenMedia: _openMedia,
      onPlayAudio: _playAudio,
      onDownloadAudio: _requestAudioFile,
      onDownloadFile: _requestFile,
      onLongPress: (details, ctx) =>
          _showMessageOptions(ctx, details.globalPosition, m, isPinned),
      onSwipeReply: () => _setReply(m),
      onQuotedTap: () {
        final id = m.quoted?.itemId;
        if (id != null) _scrollToItemId(id);
      },
    );
  }

  // =========================================================================
  // REPLY PREVIEW
  // =========================================================================

  Widget _buildReplyPreview(AppLocalizations loc) {
    final m = _replyTo!;
    return Container(
      color: _ChatTheme.composeBg,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          Container(width: 3, height: 36, color: _ChatTheme.quotedBar),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  m.fromMe ? loc.translate('you_label') : widget.chatName,
                  style: const TextStyle(
                    color: _ChatTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  m.text.isEmpty ? '(media)' : m.text.split('\n').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ChatTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: _ChatTheme.textSecondary),
            onPressed: () => setState(() => _replyTo = null),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // COMPOSE BAR
  // =========================================================================

  Widget _buildComposeBar(AppLocalizations loc) {
    final canSend = _canCompose && !_sending;
    return Container(
      color: _ChatTheme.composeBg,
      padding: EdgeInsets.only(
        left: 6,
        right: 6,
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom + 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ComposeIconButton(
            icon: Icons.add,
            onTap: canSend ? _openAttachMenu : null,
            tooltip: 'Attach',
          ),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF202126),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      focusNode: _msgFocus,
                      enabled: canSend,
                      minLines: 1,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(
                        color: _ChatTheme.textPrimary,
                        fontSize: 15,
                      ),
                      cursorColor: _ChatTheme.accent,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        hintText: _canCompose
                            ? loc.translate('message_hint')
                            : loc.translate('message_hint_wait_connection'),
                        hintStyle: const TextStyle(
                          color: _ChatTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.emoji_emotions_outlined,
                      color: _ChatTheme.textSecondary,
                    ),
                    onPressed: canSend ? _openStickerSheet : null,
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
          ),
          _ComposeSendButton(
            hasText: _composeHasText,
            sending: _sending || _sendingMedia,
            enabled: canSend,
            onSendText: _sendText,
            onCircle: _openCircleRecorder,
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // ATTACH SHEET
  // =========================================================================

  void _openAttachMenu() {
    final loc = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _ChatTheme.appBarBg,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: GridView.count(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _AttachTile(
              icon: Icons.photo_outlined,
              label: loc.translate('photo'),
              color: const Color(0xFF5A9CF5),
              onTap: () {
                Navigator.of(ctx).pop();
                _sendImages();
              },
            ),
            _AttachTile(
              icon: Icons.videocam_outlined,
              label: loc.translate('video'),
              color: const Color(0xFFE07A5F),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAndSendVideo();
              },
            ),
            _AttachTile(
              icon: Icons.audiotrack,
              label: loc.translate('audio'),
              color: const Color(0xFF81B29A),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAndSendFile(audioOnly: true);
              },
            ),
            _AttachTile(
              icon: Icons.insert_drive_file_outlined,
              label: loc.translate('file'),
              color: const Color(0xFFB888E5),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAndSendFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // STICKER SHEET
  // =========================================================================

  void _openStickerSheet() {
    final loc = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _ChatTheme.appBarBg,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.5,
            maxChildSize: 0.9,
            builder: (_, scrollCtrl) {
              final packs = _stickerStore.packs;
              if (packs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.emoji_emotions_outlined,
                          color: _ChatTheme.textSecondary,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          loc.translate('sticker_not_installed'),
                          style: const TextStyle(
                            color: _ChatTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () async {
                            final created = await _createStickerPack();
                            if (created != null) setSheet(() {});
                          },
                          child: Text(loc.translate('import')),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (_selectedPackIndex >= packs.length) {
                _selectedPackIndex = 0;
              }
              final pack = packs[_selectedPackIndex];
              return Column(
                children: [
                  Expanded(
                    child: GridView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: pack.stickers.length,
                      itemBuilder: (_, i) {
                        final s = pack.stickers[i];
                        return GestureDetector(
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _sendSticker(pack, s);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            color: Colors.transparent,
                            child: s.filePath.toLowerCase().endsWith('.webm')
                                ? StickerThumb(filePath: s.filePath)
                                : Image.file(File(s.filePath),
                                    fit: BoxFit.contain),
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    height: 56,
                    color: _ChatTheme.bg,
                    child: Row(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: packs.length,
                            itemBuilder: (_, i) {
                              final p = packs[i];
                              final selected = i == _selectedPackIndex;
                              return GestureDetector(
                                onTap: () => setSheet(
                                  () => _selectedPackIndex = i,
                                ),
                                child: Container(
                                  width: 56,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? _ChatTheme.accent.withValues(
                                            alpha: 0.2,
                                          )
                                        : Colors.transparent,
                                  ),
                                  child: p.coverPath != null
                                      ? (p.coverPath!
                                              .toLowerCase()
                                              .endsWith('.webm')
                                          ? StickerThumb(
                                              filePath: p.coverPath!,
                                            )
                                          : Image.file(File(p.coverPath!)))
                                      : const Icon(
                                          Icons.emoji_emotions_outlined,
                                          color: _ChatTheme.textSecondary,
                                        ),
                                ),
                              );
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.add,
                            color: _ChatTheme.textSecondary,
                          ),
                          onPressed: () async {
                            final created = await _createStickerPack();
                            if (created != null) setSheet(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<StickerPack?> _createStickerPack() async {
    final loc = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final authorCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _ChatTheme.appBarBg,
        title: Text(
          loc.translate('new_sticker_pack'),
          style: const TextStyle(color: _ChatTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _stickerField(nameCtrl, loc.translate('sticker_name'), onChanged: (v) {
              if (idCtrl.text.isEmpty) idCtrl.text = slugify(v);
            }),
            _stickerField(idCtrl, loc.translate('sticker_id')),
            _stickerField(authorCtrl, loc.translate('sticker_author')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.translate('sticker_next')),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
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
    return _stickerStore.createPack(
      packId: id,
      name: name,
      author: authorCtrl.text.trim().isEmpty ? null : authorCtrl.text.trim(),
      filePaths: paths,
    );
  }

  Widget _stickerField(
    TextEditingController c,
    String label, {
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller: c,
      onChanged: onChanged,
      style: const TextStyle(color: _ChatTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _ChatTheme.textSecondary),
      ),
    );
  }

  // =========================================================================
  // UTILS
  // =========================================================================

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E232A),
      ),
    );
  }
}

// =============================================================================
// PRIVATE WIDGETS
// =============================================================================

enum _DisplayKind { message, date }

class _DisplayEntry {
  final _DisplayKind kind;
  final UiMessage? message;
  final DateTime? date;

  const _DisplayEntry._(this.kind, {this.message, this.date});

  factory _DisplayEntry.message(UiMessage m) =>
      _DisplayEntry._(_DisplayKind.message, message: m);

  factory _DisplayEntry.date(DateTime d) =>
      _DisplayEntry._(_DisplayKind.date, date: d);
}

class _Avatar extends StatelessWidget {
  final String name;
  final Uint8List? image;
  final double size;

  const _Avatar({required this.name, required this.image, this.size = 32});

  String _initials() {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      final runes = parts.first.runes.toList();
      return String.fromCharCodes(runes.take(2)).toUpperCase();
    }
    final a = parts[0].runes.isEmpty
        ? ''
        : String.fromCharCodes([parts[0].runes.first]);
    final b = parts[1].runes.isEmpty
        ? ''
        : String.fromCharCodes([parts[1].runes.first]);
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: _ChatTheme.avatarBg,
      backgroundImage: image != null ? MemoryImage(image!) : null,
      child: image == null
          ? Text(
              _initials(),
              style: TextStyle(
                color: _ChatTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: size / 2.6,
              ),
            )
          : null,
    );
  }
}

class _DateChip extends StatelessWidget {
  final DateTime date;

  const _DateChip({required this.date});

  String _label(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final now = DateTime.now();
    final isToday = now.year == date.year &&
        now.month == date.month &&
        now.day == date.day;
    if (isToday) return loc.translate('today');
    final yest = now.subtract(const Duration(days: 1));
    if (yest.year == date.year &&
        yest.month == date.month &&
        yest.day == date.day) {
      return loc.translate('yesterday');
    }
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd.$mm.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _ChatTheme.dateChip,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _label(context),
          style: const TextStyle(
            color: _ChatTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SystemBanner extends StatelessWidget {
  final String text;

  const _SystemBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _ChatTheme.dateChip,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: _ChatTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _JumpToBottomButton extends StatelessWidget {
  final VoidCallback onTap;

  const _JumpToBottomButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E232A),
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.keyboard_arrow_down,
            color: _ChatTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _ComposeIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  const _ComposeIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: _ChatTheme.textSecondary),
      splashRadius: 22,
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}

class _ComposeSendButton extends StatelessWidget {
  final bool hasText;
  final bool sending;
  final bool enabled;
  final VoidCallback onSendText;
  final VoidCallback onCircle;

  const _ComposeSendButton({
    required this.hasText,
    required this.sending,
    required this.enabled,
    required this.onSendText,
    required this.onCircle,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = !enabled || sending;
    final showSend = hasText;
    final bg = showSend ? _ChatTheme.accent : const Color(0xFF202126);
    final iconColor = showSend ? Colors.white : _ChatTheme.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 2),
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: disabled
              ? null
              : (showSend ? onSendText : onCircle),
          child: SizedBox(
            width: 44,
            height: 44,
            child: sending
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    showSend ? Icons.send : Icons.fiber_manual_record,
                    color: iconColor,
                  ),
          ),
        ),
      ),
    );
  }
}

class _AttachTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: _ChatTheme.textPrimary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
