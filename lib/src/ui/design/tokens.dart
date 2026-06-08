// Design tokens for TangleX.
//
// This file is the SINGLE source of truth for colors, spacing, radii and
// durations used in the UI. Any new UI code MUST take its values from here,
// not from inline `Color(0xFF...)` / `EdgeInsets.all(7)` / `BorderRadius.circular(N)`.
//
// See DESIGN.md at the repo root for the full design system specification.
//
// Theme is dark-only (one mode). If light is added later, this file becomes
// `const`-tables for the dark variant and a parallel light file is introduced.

import 'package:flutter/material.dart';

/// Color tokens.
///
/// Naming follows the "surface ladder" pattern:
///  - [bg]       — base background, used as the chat-list / messages background
///  - [surface1] — first layer above bg: AppBar, compose bar, bottom sheets
///  - [surface2] — cards, incoming bubbles, dialogs
///  - [surface3] — hover/pressed, slightly-elevated emphasis
class AppColors {
  const AppColors._();

  // Surfaces
  static const Color bg = Color(0xFF0E0E10);
  static const Color surface1 = Color(0xFF15161A);
  static const Color surface2 = Color(0xFF1C1D22);
  static const Color surface3 = Color(0xFF23252B);

  // Dividers / borders
  static const Color divider = Color(0xFF2A2C32);
  static const Color border = Color(0xFF2A2C32);

  // Text
  static const Color textPrimary = Color(0xFFECECEC);
  static const Color textSecondary = Color(0xFF9098A3);
  static const Color textDisabled = Color(0xFF5E646D);
  static const Color textOnAccent = Color(0xFFFFFFFF);

  // Accents
  static const Color accent = Color(0xFF2AABEE);
  static const Color accentPressed = Color(0xFF1E96D4);
  static const Color accentMuted = Color(0xFF1A4C6B);

  // Bubbles
  static const Color outgoingBubble = Color(0xFF2AABEE);
  static const Color outgoingBubbleText = Color(0xFFFFFFFF);
  static const Color outgoingBubbleSecondary = Color(0xFFCDE8FA);
  static const Color incomingBubble = Color(0xFF1C1D22);
  static const Color incomingBubbleText = Color(0xFFECECEC);
  static const Color incomingBubbleSecondary = Color(0xFF9098A3);

  // Quoted / replied
  static const Color quotedAccent = Color(0xFF2AABEE);
  static const Color quotedBg = Color(0xFF23252B);

  // Status
  static const Color error = Color(0xFFE5484D);
  static const Color success = Color(0xFF46A758);
  static const Color warning = Color(0xFFF5A623);
  static const Color online = Color(0xFF46A758);

  // Avatar palette (deterministic by hash of name).
  // Telegram-like 8-tone fan.
  static const List<Color> avatarPalette = <Color>[
    Color(0xFF3390EC), // blue
    Color(0xFF46A758), // green
    Color(0xFFF5A623), // amber
    Color(0xFFE5484D), // red
    Color(0xFF9F7AEA), // violet
    Color(0xFF14B8A6), // teal
    Color(0xFFEC4899), // pink
    Color(0xFFFB923C), // orange
  ];

  /// Pick a deterministic avatar color from [seed] (typically display name).
  static Color avatarColorFor(String seed) {
    if (seed.isEmpty) return avatarPalette[0];
    int hash = 0;
    for (final cu in seed.codeUnits) {
      hash = (hash * 31 + cu) & 0x7fffffff;
    }
    return avatarPalette[hash % avatarPalette.length];
  }

  // Code blocks
  static const Color codeBg = Color(0xFF181A1F);
  static const Color codeBorder = Color(0xFF2A2C32);
  static const Color codeInlineBg = Color(0xFF23252B);

  // Scrim
  static const Color scrim = Color(0x99000000);
}

/// Spacing scale — only these values are allowed.
///
/// 4-point grid. Don't introduce arbitrary paddings — pick the closest token.
class AppSpacing {
  const AppSpacing._();

  static const double s0 = 0;
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;
}

/// Border radius scale.
class AppRadius {
  const AppRadius._();

  /// Small — input, badges, chips, icon containers.
  static const double rs = 8;

  /// Medium — cards, dialogs, media tiles.
  static const double rm = 12;

  /// Large — message bubbles, large cards.
  static const double rl = 16;

  /// Extra large — bottom sheets top corners.
  static const double rxl = 24;

  /// Effectively a circle.
  static const double rfull = 999;

  // Pre-built BorderRadius values for convenience.
  static const BorderRadius brs = BorderRadius.all(Radius.circular(rs));
  static const BorderRadius brm = BorderRadius.all(Radius.circular(rm));
  static const BorderRadius brl = BorderRadius.all(Radius.circular(rl));
  static const BorderRadius brxl = BorderRadius.all(Radius.circular(rxl));

  static const BorderRadius sheetTop = BorderRadius.only(
    topLeft: Radius.circular(rxl),
    topRight: Radius.circular(rxl),
  );

  /// Bubble radius for incoming messages: small bottom-left corner.
  static const BorderRadius bubbleIncoming = BorderRadius.only(
    topLeft: Radius.circular(rl),
    topRight: Radius.circular(rl),
    bottomLeft: Radius.circular(rs),
    bottomRight: Radius.circular(rl),
  );

  /// Bubble radius for outgoing messages: small bottom-right corner.
  static const BorderRadius bubbleOutgoing = BorderRadius.only(
    topLeft: Radius.circular(rl),
    topRight: Radius.circular(rl),
    bottomLeft: Radius.circular(rl),
    bottomRight: Radius.circular(rs),
  );
}

/// Motion / animation durations.
class AppDuration {
  const AppDuration._();

  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
}

/// Common icon sizes.
class AppIconSize {
  const AppIconSize._();

  static const double small = 20;
  static const double regular = 24;
  static const double large = 28;
}

/// Common avatar sizes.
class AppAvatarSize {
  const AppAvatarSize._();

  static const double tiny = 24;
  static const double small = 28;
  static const double medium = 36;
  static const double large = 50;
  static const double xlarge = 96;
}
