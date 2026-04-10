import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/chat_message_models.dart';

class AudioMiniPlayer extends StatelessWidget {
  final AudioPlayer player;
  final String title;
  final VoidCallback onClose;

  const AudioMiniPlayer({
    required this.player,
    required this.title,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: const Border(
          bottom: BorderSide(
            color: Color(0xFF333333),
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
                icon: Icon(
                  playing ? Icons.pause : Icons.play_arrow,
                  color: const Color(0xFF5A9CF5),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE8E8E8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                StreamBuilder<Duration?>(
                  stream: player.durationStream,
                  builder: (context, durSnap) {
                    final dur = durSnap.data ?? Duration.zero;
                    return StreamBuilder<Duration>(
                      stream: player.positionStream,
                      builder: (context, posSnap) {
                        final pos = posSnap.data ?? Duration.zero;
                        final value = dur.inMilliseconds == 0
                            ? 0.0
                            : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
                        return Column(
                          children: [
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                activeTrackColor: const Color(0xFF5A9CF5),
                                inactiveTrackColor: const Color(0xFF333333),
                                thumbColor: const Color(0xFF5A9CF5),
                              ),
                              child: Slider(
                                value: value,
                                onChanged: dur.inMilliseconds == 0
                                    ? null
                                    : (val) {
                                        final ms = (val * dur.inMilliseconds).toInt();
                                        player.seek(Duration(milliseconds: ms));
                                      },
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_fmt(pos),
                                    style: const TextStyle(
                                      color: Color(0xFF808080),
                                    )),
                                Text(_fmt(dur),
                                    style: const TextStyle(
                                      color: Color(0xFF808080),
                                    )),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Color(0xFF808080)),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class AudioBubble extends StatelessWidget {
  final AudioItem audio;
  final bool fromMe;
  final VoidCallback onPlay;
  final VoidCallback onDownload;
  final AudioPlayer audioPlayer;
  final AudioNowPlaying? nowPlaying;
  final Color textPrimary;
  final Color textSecondary;

  const AudioBubble({
    required this.audio,
    required this.fromMe,
    required this.onPlay,
    required this.onDownload,
    required this.audioPlayer,
    required this.nowPlaying,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleColor = textPrimary;
    final subtitleColor = textSecondary;
    final isCurrent = nowPlaying?.filePath == audio.filePath;
    final canPlay = audio.filePath != null;
    final isMissing = !canPlay && audio.fileId != null && !fromMe;
    final showProgress = (audio.fileStatusType == 'rcvTransfer' || audio.fileStatusType == 'sndTransfer') &&
        (audio.transferTotal != null && audio.transferTotal! > 0) &&
        audio.transferProgress != null;
    final progress = showProgress ? (audio.transferProgress! / audio.transferTotal!) : null;
    final playBtnBg = fromMe
        ? const Color(0xFF5A9CF5)
        : const Color(0xFF2A2A2A);

    return StreamBuilder<PlayerState>(
      stream: audioPlayer.playerStateStream,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? false;
        final showPause = isCurrent && playing;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkResponse(
              onTap: canPlay ? onPlay : (isMissing ? onDownload : null),
              radius: 20,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: playBtnBg,
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isMissing || showProgress)
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: progress,
                          color: const Color(0xFF5A9CF5),
                        ),
                      ),
                    Icon(
                      isMissing ? Icons.download : (showPause ? Icons.pause : Icons.play_arrow),
                      color: fromMe ? Colors.white : const Color(0xFF5A9CF5),
                      size: 20,
                    ),
                  ],
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
                      color: titleColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _buildSubtitle(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isCurrent && playing ? const Color(0xFF5A9CF5) : subtitleColor,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _buildSubtitle() {
    final size = audio.fileSize != null ? _formatSize(audio.fileSize!) : null;
    final base = size != null ? '00:00, $size' : '00:00';
    return base;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes} B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }
}
