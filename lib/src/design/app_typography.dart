import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// Text styles follow Telegram's scale: 13 px on desktop, 16 dp on phone,
/// with metadata one step smaller.
@immutable
class AppTypography {
  const AppTypography({
    required this.baseSize,
    required this.fontFamily,
    required this.chatTitle,
    required this.listName,
    required this.listPreview,
    required this.listTime,
    required this.message,
    required this.messageMeta,
    required this.sender,
    required this.service,
    required this.button,
    required this.badge,
    required this.sectionHeader,
    required this.input,
  });

  static const double desktopBase = 13;
  static const double phoneBase = 16;

  final double baseSize;
  final String? fontFamily;
  final TextStyle chatTitle;
  final TextStyle listName;
  final TextStyle listPreview;
  final TextStyle listTime;
  final TextStyle message;
  final TextStyle messageMeta;
  final TextStyle sender;
  final TextStyle service;
  final TextStyle button;
  final TextStyle badge;
  final TextStyle sectionHeader;
  final TextStyle input;

  static TextStyle _s(
    String? family,
    double size, {
    FontWeight weight = FontWeight.w400,
    double height = 1.3,
    double? spacing,
  }) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        decoration: TextDecoration.none,
      );

  /// Telegram Desktop scale: 13 px base, 12 px metadata.
  factory AppTypography.standard({double baseSize = 13, String? family}) =>
      AppTypography(
        baseSize: baseSize,
        fontFamily: family,
        chatTitle:
            _s(family, baseSize + 2, weight: FontWeight.w600, height: 1.2),
        listName: _s(family, baseSize, weight: FontWeight.w600, height: 1.2),
        listPreview: _s(family, baseSize, height: 1.25),
        listTime: _s(family, baseSize - 1, height: 1.2),
        message: _s(family, baseSize, height: 1.45),
        messageMeta: _s(family, baseSize - 1, height: 1.2),
        sender: _s(family, baseSize - 1, weight: FontWeight.w600, height: 1.2),
        service: _s(family, baseSize - 1, weight: FontWeight.w600, height: 1.3),
        button: _s(family, baseSize, weight: FontWeight.w600, height: 1.2),
        badge: _s(family, 12, weight: FontWeight.w700, height: 1.0),
        sectionHeader:
            _s(family, baseSize - 1, weight: FontWeight.w600, height: 1.2),
        input: _s(family, baseSize, height: 1.35),
      );

  /// Telegram Android scale: 16 dp messages, 15 dp previews, 12 dp metadata.
  factory AppTypography.phone({double scale = 1, String? family}) =>
      AppTypography(
        baseSize: phoneBase * scale,
        fontFamily: family,
        chatTitle: _s(family, 20 * scale, weight: FontWeight.w600, height: 1.2),
        listName: _s(family, 16 * scale, weight: FontWeight.w600, height: 1.2),
        listPreview: _s(family, 15 * scale, height: 1.25),
        listTime: _s(family, 12 * scale, height: 1.2),
        message: _s(family, 16 * scale, height: 1.35),
        messageMeta: _s(family, 12 * scale, height: 1.2),
        sender: _s(family, 14 * scale, weight: FontWeight.w600, height: 1.2),
        service: _s(family, 13 * scale, weight: FontWeight.w600, height: 1.3),
        button: _s(family, 14 * scale, weight: FontWeight.w600, height: 1.2),
        badge: _s(family, 12 * scale, weight: FontWeight.w700, height: 1.0),
        sectionHeader:
            _s(family, 14 * scale, weight: FontWeight.w600, height: 1.2),
        input: _s(family, 16 * scale, height: 1.35),
      );

  AppTypography get forPhone =>
      AppTypography.phone(scale: baseSize / desktopBase, family: fontFamily);

  static AppTypography lerp(AppTypography a, AppTypography b, double t) =>
      AppTypography(
        baseSize: a.baseSize + (b.baseSize - a.baseSize) * t,
        fontFamily: t < 0.5 ? a.fontFamily : b.fontFamily,
        chatTitle: TextStyle.lerp(a.chatTitle, b.chatTitle, t)!,
        listName: TextStyle.lerp(a.listName, b.listName, t)!,
        listPreview: TextStyle.lerp(a.listPreview, b.listPreview, t)!,
        listTime: TextStyle.lerp(a.listTime, b.listTime, t)!,
        message: TextStyle.lerp(a.message, b.message, t)!,
        messageMeta: TextStyle.lerp(a.messageMeta, b.messageMeta, t)!,
        sender: TextStyle.lerp(a.sender, b.sender, t)!,
        service: TextStyle.lerp(a.service, b.service, t)!,
        button: TextStyle.lerp(a.button, b.button, t)!,
        badge: TextStyle.lerp(a.badge, b.badge, t)!,
        sectionHeader: TextStyle.lerp(a.sectionHeader, b.sectionHeader, t)!,
        input: TextStyle.lerp(a.input, b.input, t)!,
      );
}
