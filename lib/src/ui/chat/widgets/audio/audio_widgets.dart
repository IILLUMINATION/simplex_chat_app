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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D232A) : const Color(0xFFF0F6FF),
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
                icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: isDark ? Colors.white : const Color(0xFF1A73E8)),
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
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isDark ? Colors.white : const Color(0xFF1D1F23),
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
                                activeTrackColor: isDark ? const Color(0xFF64B5FF) : const Color(0xFF1A73E8),
                                inactiveTrackColor: isDark
                                    ? Colors.white.withOpacity(0.15)
                                    : const Color(0xFFBFDDFB),
                                thumbColor: isDark ? const Color(0xFF64B5FF) : const Color(0xFF1A73E8),
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
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: isDark ? Colors.white70 : const Color(0xFF5F6368),
                                    )),
                                Text(_fmt(dur),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: isDark ? Colors.white70 : const Color(0xFF5F6368),
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
            icon: Icon(Icons.close, color: isDark ? Colors.white70 : const Color(0xFF5F6368)),
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
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = textPrimary;
    final subtitleColor = textSecondary;
    final isCurrent = nowPlaying?.filePath == audio.filePath;
    final canPlay = audio.filePath != null;
    final isMissing = !canPlay && audio.fileId != null && !fromMe;
    final showProgress = (audio.fileStatusType == 'rcvTransfer' || audio.fileStatusType == 'sndTransfer') &&
        (audio.transferTotal != null && audio.transferTotal! > 0);
    final progress = showProgress ? (audio.transferProgress! / audio.transferTotal!) : null;

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
                  color: fromMe
                      ? const Color(0xFF2AABEE)
                      : (isDark ? const Color(0xFF2A2F36) : const Color(0xFFE2E8F0)),
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
                        ),
                      ),
                    Icon(
                      isMissing ? Icons.download : (showPause ? Icons.pause : Icons.play_arrow),
                      color: fromMe ? Colors.white : (isDark ? Colors.white : const Color(0xFF2A7ABF)),
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
                      color: isCurrent && playing ? const Color(0xFF2AABEE) : subtitleColor,
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
