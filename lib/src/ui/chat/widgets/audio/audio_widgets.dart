import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../design/design.dart';
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
        color: AppColors.surface1,
        border: const Border(
          bottom: BorderSide(
            color: AppColors.divider,
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
                  color: AppColors.accent,
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
                    color: AppColors.textPrimary,
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
                                activeTrackColor: AppColors.accent,
                                inactiveTrackColor: AppColors.divider,
                                thumbColor: AppColors.accent,
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
                                      color: AppColors.textSecondary,
                                    )),
                                Text(_fmt(dur),
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
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
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
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
    final awaitingSender = !fromMe &&
        !canPlay &&
        audio.fileId != null &&
        audio.fileStatusType == 'rcvInvitation' &&
        audio.fileSize == null;
    final isMissing = !canPlay && audio.fileId != null && !fromMe && !awaitingSender;
    final showProgress = audio.transferTotal != null &&
        audio.transferTotal! > 0 &&
        audio.transferProgress != null;
    final progress = showProgress ? (audio.transferProgress! / audio.transferTotal!) : null;
    final playBtnBg = fromMe
        ? AppColors.accent
        : AppColors.surface3;

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
                    if (awaitingSender)
                      const Icon(Icons.hourglass_empty, color: AppColors.accent, size: 18),
                    if (!awaitingSender && (isMissing || showProgress))
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: progress,
                          color: AppColors.accent,
                        ),
                      ),
                    Icon(
                      isMissing ? Icons.download : (showPause ? Icons.pause : Icons.play_arrow),
                      color: fromMe ? Colors.white : AppColors.accent,
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
                      color: isCurrent && playing ? AppColors.accent : subtitleColor,
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
