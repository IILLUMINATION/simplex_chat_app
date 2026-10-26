import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design/app_theme.dart';

/// Telegram-style peer avatar: deterministic gradient derived from the peer id,
/// with initials on top of it.
class PeerAvatar extends StatelessWidget {
  const PeerAvatar({
    super.key,
    required this.seed,
    required this.title,
    required this.size,
    this.online = false,
    this.fontSize,
    this.imageBytes,
  });

  final String seed;
  final String title;
  final double size;
  final bool online;
  final double? fontSize;
  final Uint8List? imageBytes;

  static const _palettes = <List<Color>>[
    [Color(0xFFFF8850), Color(0xFFFFCD6E)],
    [Color(0xFFFF5E7E), Color(0xFFFF7A45)],
    [Color(0xFF6A85F1), Color(0xFF8F6ED5)],
    [Color(0xFF56CCF2), Color(0xFF2F80ED)],
    [Color(0xFF43E97B), Color(0xFF38F9D7)],
    [Color(0xFFB06AB3), Color(0xFF4568DC)],
    [Color(0xFFF093FB), Color(0xFFF5576C)],
    [Color(0xFF30CFD0), Color(0xFF330867)],
  ];

  List<Color> get _colors {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _palettes[hash % _palettes.length];
  }

  String get _initials {
    final words = title.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    if (words.length == 1) {
      return words.first.substring(0, 1).toUpperCase();
    }
    final first = words.first.substring(0, 1);
    final last = words.last.substring(0, 1);
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final colors = _colors;
    final diameter = size;
    final picture = imageBytes;
    final avatar = Container(
      width: diameter,
      height: diameter,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        image: picture == null
            ? null
            : DecorationImage(image: MemoryImage(picture), fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: picture != null
          ? null
          : Text(
              _initials,
              style: theme.typography.listName.copyWith(
                fontSize: fontSize ?? diameter * 0.38,
                color: Colors.white,
              ),
            ),
    );

    if (!online) return avatar;

    final dot = diameter * 0.22;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: theme.palette.online,
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.palette.windowBg,
                width: dot * 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
