// Single canonical avatar widget.
//
// Renders either:
//  - the provided image bytes (if any)
//  - or a colored circle with up to two-letter initials
//
// Supports a small "online" dot and a group-chat variant.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../tokens.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.size = AppAvatarSize.large,
    this.imageBytes,
    this.isGroup = false,
    this.online = false,
  });

  final String name;
  final double size;
  final Uint8List? imageBytes;
  final bool isGroup;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.avatarColorFor(name);
    final Widget body = (imageBytes != null && imageBytes!.isNotEmpty)
        ? ClipOval(
            child: Image.memory(
              imageBytes!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _fallback(color),
            ),
          )
        : _fallback(color);

    if (!online) return body;

    final dotSize = (size * 0.27).clamp(8.0, 14.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback(Color color) {
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: color,
        alignment: Alignment.center,
        child: isGroup
            ? Icon(
                Icons.people_alt_rounded,
                color: AppColors.textOnAccent,
                size: size * 0.5,
              )
            : Text(
                _initials(name),
                style: TextStyle(
                  color: AppColors.textOnAccent,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
      ),
    );
  }

  static String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts =
        trimmed.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.length == 1) {
      final p = parts.first;
      return p.characters.take(1).toString().toUpperCase();
    }
    final a = parts.first.characters.take(1).toString();
    final b = parts.last.characters.take(1).toString();
    return (a + b).toUpperCase();
  }
}
