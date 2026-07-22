// TangleX — single avatar widget.
//
// Per HANDOFF.md § 10, the whole app uses ONE avatar widget. If an image is
// available, render it. Otherwise render initials over a tonal background
// derived from the display name — keeps colors deterministic per contact and
// stays inside the Material 3 palette by using `secondaryContainer` tones.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/chat_message_parser.dart' as parser;

class TxAvatar extends StatelessWidget {
  const TxAvatar({
    super.key,
    required this.name,
    this.image,
    this.size = 44,
  });

  final String name;
  final Uint8List? image;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initials = parser.initials(name).toUpperCase();
    final bg = colorScheme.secondaryContainer;
    final fg = colorScheme.onSecondaryContainer;

    if (image != null && image!.isNotEmpty) {
      return ClipOval(
        child: Image.memory(
          image!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) =>
              _initialsCircle(initials, bg, fg, size),
        ),
      );
    }
    return _initialsCircle(initials, bg, fg, size);
  }

  static Widget _initialsCircle(
    String initials,
    Color bg,
    Color fg,
    double size,
  ) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        initials.isEmpty ? '·' : initials,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}
