import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/chat_message_models.dart';

class AudioMiniPlayer extends StatelessWidget {
  final AudioPlayer player;
  final String title;

  const AudioMiniPlayer({
    required this.player,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1D) : theme.colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? const Color(0xFF38383A).withOpacity(0.5)
                : theme.colorScheme.outline.withOpacity(0.15),
          ),
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

class AudioBubble extends StatelessWidget {
  final AudioItem audio;
  final bool fromMe;
  final VoidCallback onPlay;
  final AudioPlayer audioPlayer;
  final AudioNowPlaying? nowPlaying;

  const AudioBubble({
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
          if (isNowPlaying) ...[
            const SizedBox(height: 8),
            AudioSliderWidget(
              audioPlayer: audioPlayer,
              theme: theme,
            ),
          ],
        ],
      ),
    );
  }
}

class AudioSliderWidget extends StatefulWidget {
  final AudioPlayer audioPlayer;
  final ThemeData theme;

  const AudioSliderWidget({required this.audioPlayer, required this.theme});

  @override
  State<AudioSliderWidget> createState() => _AudioSliderWidgetState();
}

class _AudioSliderWidgetState extends State<AudioSliderWidget> {
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
