import 'package:flutter/widgets.dart';

/// Layout constants from Telegram Desktop (`dialogs.style`, `chat.style`,
/// `window.style`) with the phone variants from Telegram Android
/// (`DialogCell`, `ChatMessageCell`, `SharedConfig`).
@immutable
class AppMetrics {
  const AppMetrics({
    required this.compact,
    required this.listRowHeight,
    required this.listPadding,
    required this.avatarSize,
    required this.avatarTextGap,
    required this.avatarRadius,
    required this.topBarHeight,
    required this.composeBarHeight,
    required this.composeFieldMaxHeight,
    required this.bubbleMaxWidth,
    required this.bubbleMinWidth,
    required this.bubbleRadius,
    required this.bubbleTailRadius,
    required this.bubblePadding,
    required this.bubbleMargin,
    required this.bubbleShadowOffset,
    required this.messageGroupGap,
    required this.attachedGap,
    required this.replyBarWidth,
    required this.replyBarHeight,
    required this.replyPadding,
    required this.replyPreviewSize,
    required this.badgeHeight,
    required this.badgePadding,
    required this.iconSize,
    required this.searchHeight,
    required this.searchRadius,
    required this.leftColumnMin,
    required this.leftColumnMax,
    required this.chatColumnMin,
    required this.thirdColumnMin,
    required this.thirdColumnMax,
    required this.twoColumnBreakpoint,
    required this.threeColumnBreakpoint,
    required this.stickerMaxSize,
    required this.roundVideoSize,
  });

  /// Phone-sized metrics (bottom navigation, taller rows).
  final bool compact;

  final double listRowHeight;
  final EdgeInsets listPadding;
  final double avatarSize;
  final double avatarTextGap;
  final double avatarRadius;
  final double topBarHeight;
  final double composeBarHeight;
  final double composeFieldMaxHeight;
  final double bubbleMaxWidth;
  final double bubbleMinWidth;
  final double bubbleRadius;
  final double bubbleTailRadius;
  final EdgeInsets bubblePadding;
  final EdgeInsets bubbleMargin;
  final double bubbleShadowOffset;
  final double messageGroupGap;
  final double attachedGap;
  final double replyBarWidth;
  final double replyBarHeight;
  final EdgeInsets replyPadding;
  final double replyPreviewSize;
  final double badgeHeight;
  final EdgeInsets badgePadding;
  final double iconSize;
  final double searchHeight;
  final double searchRadius;
  final double leftColumnMin;
  final double leftColumnMax;
  final double chatColumnMin;
  final double thirdColumnMin;
  final double thirdColumnMax;
  final double twoColumnBreakpoint;
  final double threeColumnBreakpoint;
  final double stickerMaxSize;
  final double roundVideoSize;

  static const AppMetrics desktop = AppMetrics(
    compact: false,
    listRowHeight: 62,
    listPadding: EdgeInsets.fromLTRB(10, 8, 10, 8),
    avatarSize: 46,
    avatarTextGap: 12,
    avatarRadius: 23,
    topBarHeight: 54,
    composeBarHeight: 54,
    composeFieldMaxHeight: 224,
    bubbleMaxWidth: 430,
    bubbleMinWidth: 160,
    bubbleRadius: 16,
    bubbleTailRadius: 6,
    bubblePadding: EdgeInsets.fromLTRB(11, 8, 11, 8),
    bubbleMargin: EdgeInsets.fromLTRB(16, 6, 16, 2),
    bubbleShadowOffset: 2,
    messageGroupGap: 6,
    attachedGap: 2,
    replyBarWidth: 2,
    replyBarHeight: 36,
    replyPadding: EdgeInsets.fromLTRB(6, 6, 11, 6),
    replyPreviewSize: 32,
    badgeHeight: 19,
    badgePadding: EdgeInsets.symmetric(horizontal: 5),
    iconSize: 20,
    searchHeight: 35,
    searchRadius: 18,
    leftColumnMin: 260,
    leftColumnMax: 540,
    chatColumnMin: 380,
    thirdColumnMin: 292,
    thirdColumnMax: 392,
    twoColumnBreakpoint: 640,
    threeColumnBreakpoint: 932,
    stickerMaxSize: 224,
    roundVideoSize: 240,
  );

  static const AppMetrics phone = AppMetrics(
    compact: true,
    listRowHeight: 70,
    listPadding: EdgeInsets.fromLTRB(11, 0, 15, 0),
    avatarSize: 56,
    avatarTextGap: 11,
    avatarRadius: 28,
    topBarHeight: 56,
    composeBarHeight: 56,
    composeFieldMaxHeight: 160,
    bubbleMaxWidth: 430,
    bubbleMinWidth: 120,
    bubbleRadius: 17,
    bubbleTailRadius: 6,
    bubblePadding: EdgeInsets.fromLTRB(11, 8, 11, 8),
    bubbleMargin: EdgeInsets.fromLTRB(8, 4, 8, 1),
    bubbleShadowOffset: 2,
    messageGroupGap: 4,
    attachedGap: 1,
    replyBarWidth: 2,
    replyBarHeight: 34,
    replyPadding: EdgeInsets.fromLTRB(6, 4, 8, 4),
    replyPreviewSize: 30,
    badgeHeight: 20,
    badgePadding: EdgeInsets.symmetric(horizontal: 6),
    iconSize: 24,
    searchHeight: 40,
    searchRadius: 20,
    leftColumnMin: 260,
    leftColumnMax: 540,
    chatColumnMin: 380,
    thirdColumnMin: 292,
    thirdColumnMax: 392,
    twoColumnBreakpoint: 640,
    threeColumnBreakpoint: 932,
    stickerMaxSize: 200,
    roundVideoSize: 200,
  );

  static AppMetrics forWidth(double width) =>
      width < 600 ? phone : desktop;

  AppMetrics withBubbleRadius(double radius) => AppMetrics(
        compact: compact,
        listRowHeight: listRowHeight,
        listPadding: listPadding,
        avatarSize: avatarSize,
        avatarTextGap: avatarTextGap,
        avatarRadius: avatarRadius,
        topBarHeight: topBarHeight,
        composeBarHeight: composeBarHeight,
        composeFieldMaxHeight: composeFieldMaxHeight,
        bubbleMaxWidth: bubbleMaxWidth,
        bubbleMinWidth: bubbleMinWidth,
        bubbleRadius: radius,
        bubbleTailRadius: radius < bubbleTailRadius ? radius : bubbleTailRadius,
        bubblePadding: bubblePadding,
        bubbleMargin: bubbleMargin,
        bubbleShadowOffset: bubbleShadowOffset,
        messageGroupGap: messageGroupGap,
        attachedGap: attachedGap,
        replyBarWidth: replyBarWidth,
        replyBarHeight: replyBarHeight,
        replyPadding: replyPadding,
        replyPreviewSize: replyPreviewSize,
        badgeHeight: badgeHeight,
        badgePadding: badgePadding,
        iconSize: iconSize,
        searchHeight: searchHeight,
        searchRadius: searchRadius,
        leftColumnMin: leftColumnMin,
        leftColumnMax: leftColumnMax,
        chatColumnMin: chatColumnMin,
        thirdColumnMin: thirdColumnMin,
        thirdColumnMax: thirdColumnMax,
        twoColumnBreakpoint: twoColumnBreakpoint,
        threeColumnBreakpoint: threeColumnBreakpoint,
        stickerMaxSize: stickerMaxSize,
        roundVideoSize: roundVideoSize,
      );

  static AppMetrics lerp(AppMetrics a, AppMetrics b, double t) => AppMetrics(
        compact: t < 0.5 ? a.compact : b.compact,
        listRowHeight: _d(a.listRowHeight, b.listRowHeight, t),
        listPadding: EdgeInsets.lerp(a.listPadding, b.listPadding, t)!,
        avatarSize: _d(a.avatarSize, b.avatarSize, t),
        avatarTextGap: _d(a.avatarTextGap, b.avatarTextGap, t),
        avatarRadius: _d(a.avatarRadius, b.avatarRadius, t),
        topBarHeight: _d(a.topBarHeight, b.topBarHeight, t),
        composeBarHeight: _d(a.composeBarHeight, b.composeBarHeight, t),
        composeFieldMaxHeight:
            _d(a.composeFieldMaxHeight, b.composeFieldMaxHeight, t),
        bubbleMaxWidth: _d(a.bubbleMaxWidth, b.bubbleMaxWidth, t),
        bubbleMinWidth: _d(a.bubbleMinWidth, b.bubbleMinWidth, t),
        bubbleRadius: _d(a.bubbleRadius, b.bubbleRadius, t),
        bubbleTailRadius: _d(a.bubbleTailRadius, b.bubbleTailRadius, t),
        bubblePadding: EdgeInsets.lerp(a.bubblePadding, b.bubblePadding, t)!,
        bubbleMargin: EdgeInsets.lerp(a.bubbleMargin, b.bubbleMargin, t)!,
        bubbleShadowOffset: _d(a.bubbleShadowOffset, b.bubbleShadowOffset, t),
        messageGroupGap: _d(a.messageGroupGap, b.messageGroupGap, t),
        attachedGap: _d(a.attachedGap, b.attachedGap, t),
        replyBarWidth: _d(a.replyBarWidth, b.replyBarWidth, t),
        replyBarHeight: _d(a.replyBarHeight, b.replyBarHeight, t),
        replyPadding: EdgeInsets.lerp(a.replyPadding, b.replyPadding, t)!,
        replyPreviewSize: _d(a.replyPreviewSize, b.replyPreviewSize, t),
        badgeHeight: _d(a.badgeHeight, b.badgeHeight, t),
        badgePadding: EdgeInsets.lerp(a.badgePadding, b.badgePadding, t)!,
        iconSize: _d(a.iconSize, b.iconSize, t),
        searchHeight: _d(a.searchHeight, b.searchHeight, t),
        searchRadius: _d(a.searchRadius, b.searchRadius, t),
        leftColumnMin: _d(a.leftColumnMin, b.leftColumnMin, t),
        leftColumnMax: _d(a.leftColumnMax, b.leftColumnMax, t),
        chatColumnMin: _d(a.chatColumnMin, b.chatColumnMin, t),
        thirdColumnMin: _d(a.thirdColumnMin, b.thirdColumnMin, t),
        thirdColumnMax: _d(a.thirdColumnMax, b.thirdColumnMax, t),
        twoColumnBreakpoint: _d(a.twoColumnBreakpoint, b.twoColumnBreakpoint, t),
        threeColumnBreakpoint:
            _d(a.threeColumnBreakpoint, b.threeColumnBreakpoint, t),
        stickerMaxSize: _d(a.stickerMaxSize, b.stickerMaxSize, t),
        roundVideoSize: _d(a.roundVideoSize, b.roundVideoSize, t),
      );

  static double _d(double a, double b, double t) => a + (b - a) * t;
}

/// Motion constants from `basic.style` and `widgets.style` of Telegram Desktop.
@immutable
class AppMotion {
  const AppMotion({
    required this.slide,
    required this.wrap,
    required this.universal,
    required this.filter,
    required this.itemReveal,
    required this.dateFade,
    required this.rippleShow,
    required this.rippleHide,
    required this.onlinePulse,
  });

  final Duration slide;
  final Duration wrap;
  final Duration universal;
  final Duration filter;
  final Duration itemReveal;
  final Duration dateFade;
  final Duration rippleShow;
  final Duration rippleHide;
  final Duration onlinePulse;

  static const AppMotion standard = AppMotion(
    slide: Duration(milliseconds: 240),
    wrap: Duration(milliseconds: 150),
    universal: Duration(milliseconds: 120),
    filter: Duration(milliseconds: 200),
    itemReveal: Duration(milliseconds: 150),
    dateFade: Duration(milliseconds: 200),
    rippleShow: Duration(milliseconds: 200),
    rippleHide: Duration(milliseconds: 200),
    onlinePulse: Duration(milliseconds: 150),
  );

  static const Curve ease = Curves.easeOutCubic;
}
