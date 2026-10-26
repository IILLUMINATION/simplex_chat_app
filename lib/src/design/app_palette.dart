import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// Color tokens taken from Telegram Desktop's `colors.tdesktop-theme`
/// (day/night) and Telegram Android's `ThemeColors`/`night.attheme`.
///
/// Nothing in the UI may use raw colors: widgets read the palette from
/// [AppThemeScope] so every value stays user-overridable.
@immutable
class AppPalette {
  const AppPalette({
    required this.windowBg,
    required this.windowBgOver,
    required this.windowBgRipple,
    required this.accent,
    required this.accentOver,
    required this.accentRipple,
    required this.onAccent,
    required this.text,
    required this.textSecondary,
    required this.link,
    required this.error,
    required this.online,
    required this.icon,
    required this.iconActive,
    required this.divider,
    required this.topBarBg,
    required this.composeBg,
    required this.searchBg,
    required this.searchHint,
    required this.listRowHover,
    required this.listRowSelected,
    required this.listName,
    required this.listNameSelected,
    required this.listDate,
    required this.listPreview,
    required this.listSender,
    required this.badge,
    required this.badgeMuted,
    required this.badgeText,
    required this.bubbleIn,
    required this.bubbleOut,
    required this.bubbleInSelected,
    required this.bubbleOutSelected,
    required this.bubbleTextIn,
    required this.bubbleTextOut,
    required this.timeIn,
    required this.timeOut,
    required this.ticksOut,
    required this.replyBarIn,
    required this.replyBarOut,
    required this.serviceBg,
    required this.serviceText,
    required this.datePillBg,
    required this.chatWallpaper,
  });

  final Color windowBg;
  final Color windowBgOver;
  final Color windowBgRipple;
  final Color accent;
  final Color accentOver;
  final Color accentRipple;
  final Color onAccent;
  final Color text;
  final Color textSecondary;
  final Color link;
  final Color error;
  final Color online;
  final Color icon;
  final Color iconActive;
  final Color divider;
  final Color topBarBg;
  final Color composeBg;
  final Color searchBg;
  final Color searchHint;

  final Color listRowHover;
  final Color listRowSelected;
  final Color listName;
  final Color listNameSelected;
  final Color listDate;
  final Color listPreview;
  final Color listSender;
  final Color badge;
  final Color badgeMuted;
  final Color badgeText;

  final Color bubbleIn;
  final Color bubbleOut;
  final Color bubbleInSelected;
  final Color bubbleOutSelected;
  final Color bubbleTextIn;
  final Color bubbleTextOut;
  final Color timeIn;
  final Color timeOut;
  final Color ticksOut;
  final Color replyBarIn;
  final Color replyBarOut;
  final Color serviceBg;
  final Color serviceText;
  final Color datePillBg;
  final Color chatWallpaper;

  static const AppPalette day = AppPalette(
    windowBg: Color(0xFFFFFFFF),
    windowBgOver: Color(0xFFF1F1F1),
    windowBgRipple: Color(0xFFE5E5E5),
    accent: Color(0xFF40A7E3),
    accentOver: Color(0xFF39A5DB),
    accentRipple: Color(0xFF2095D0),
    onAccent: Color(0xFFFFFFFF),
    text: Color(0xFF000000),
    textSecondary: Color(0xFF999999),
    link: Color(0xFF168ACD),
    error: Color(0xFFD84D4D),
    online: Color(0xFF4DC920),
    icon: Color(0xFF999999),
    iconActive: Color(0xFF168ACD),
    divider: Color(0xFFF1F1F1),
    topBarBg: Color(0xFFFFFFFF),
    composeBg: Color(0xFFFFFFFF),
    searchBg: Color(0xFFF1F1F1),
    searchHint: Color(0xFF999999),
    listRowHover: Color(0xFFF1F1F1),
    listRowSelected: Color(0xFF419FD9),
    listName: Color(0xFF222222),
    listNameSelected: Color(0xFFFFFFFF),
    listDate: Color(0xFF999999),
    listPreview: Color(0xFF999999),
    listSender: Color(0xFF168ACD),
    badge: Color(0xFF40A7E3),
    badgeMuted: Color(0xFFBBBBBB),
    badgeText: Color(0xFFFFFFFF),
    bubbleIn: Color(0xFFFFFFFF),
    bubbleOut: Color(0xFFEFFDDE),
    bubbleInSelected: Color(0xFFC2DCF2),
    bubbleOutSelected: Color(0xFFCBEBB5),
    bubbleTextIn: Color(0xFF000000),
    bubbleTextOut: Color(0xFF000000),
    timeIn: Color(0xFFA0ACB6),
    timeOut: Color(0xFF6FAB69),
    ticksOut: Color(0xFF5AB54E),
    replyBarIn: Color(0xFF37A1DE),
    replyBarOut: Color(0xFF64B05C),
    serviceBg: Color(0x90527C41),
    serviceText: Color(0xFFFFFFFF),
    datePillBg: Color(0x90527C41),
    chatWallpaper: Color(0xFFF2F5F7),
  );

  /// Telegram Desktop's `day-blue`: same layout, blue outgoing bubbles
  /// instead of the classic green.
  static const AppPalette dayBlue = AppPalette(
    windowBg: Color(0xFFFFFFFF),
    windowBgOver: Color(0xFFF1F1F1),
    windowBgRipple: Color(0xFFE5E5E5),
    accent: Color(0xFF40A7E3),
    accentOver: Color(0xFF39A5DB),
    accentRipple: Color(0xFF2095D0),
    onAccent: Color(0xFFFFFFFF),
    text: Color(0xFF000000),
    textSecondary: Color(0xFF999999),
    link: Color(0xFF168ACD),
    error: Color(0xFFD84D4D),
    online: Color(0xFF4DC920),
    icon: Color(0xFF999999),
    iconActive: Color(0xFF168ACD),
    divider: Color(0xFFF1F1F1),
    topBarBg: Color(0xFFFFFFFF),
    composeBg: Color(0xFFFFFFFF),
    searchBg: Color(0xFFF1F1F1),
    searchHint: Color(0xFF999999),
    listRowHover: Color(0xFFF1F1F1),
    listRowSelected: Color(0xFF419FD9),
    listName: Color(0xFF222222),
    listNameSelected: Color(0xFFFFFFFF),
    listDate: Color(0xFF999999),
    listPreview: Color(0xFF999999),
    listSender: Color(0xFF168ACD),
    badge: Color(0xFF40A7E3),
    badgeMuted: Color(0xFFBBBBBB),
    badgeText: Color(0xFFFFFFFF),
    bubbleIn: Color(0xFFFFFFFF),
    bubbleOut: Color(0xFFDEF1FD),
    bubbleInSelected: Color(0xFFBBE1FC),
    bubbleOutSelected: Color(0xFFBBE1FC),
    bubbleTextIn: Color(0xFF000000),
    bubbleTextOut: Color(0xFF000000),
    timeIn: Color(0xFFA0ACB6),
    timeOut: Color(0xFF86A8C2),
    ticksOut: Color(0xFF059DE8),
    replyBarIn: Color(0xFF37A1DE),
    replyBarOut: Color(0xFF059DE8),
    serviceBg: Color(0x59005180),
    serviceText: Color(0xFFFFFFFF),
    datePillBg: Color(0x59005180),
    chatWallpaper: Color(0xFFF2F5F7),
  );

  static const AppPalette night = AppPalette(
    windowBg: Color(0xFF17212B),
    windowBgOver: Color(0xFF232E3C),
    windowBgRipple: Color(0xFF24303D),
    accent: Color(0xFF5288C1),
    accentOver: Color(0xFF3476AB),
    accentRipple: Color(0xFF3B7CB1),
    onAccent: Color(0xFFFFFFFF),
    text: Color(0xFFF5F5F5),
    textSecondary: Color(0xFF708499),
    link: Color(0xFF6AB3F3),
    error: Color(0xFFDC3D3D),
    online: Color(0xFF63B6FF),
    icon: Color(0xFF6C7883),
    iconActive: Color(0xFF6AB3F3),
    divider: Color(0xFF232F39),
    topBarBg: Color(0xFF17212B),
    composeBg: Color(0xFF17212B),
    searchBg: Color(0xFF242F3D),
    searchHint: Color(0xFF6D7883),
    listRowHover: Color(0xFF202B36),
    listRowSelected: Color(0xFF2B5278),
    listName: Color(0xFFF5F5F5),
    listNameSelected: Color(0xFFFFFFFF),
    listDate: Color(0xFF8696A8),
    listPreview: Color(0xFF7F91A4),
    listSender: Color(0xFF73B9F5),
    badge: Color(0xFF4082BC),
    badgeMuted: Color(0xFF3E546A),
    badgeText: Color(0xFFFFFFFF),
    bubbleIn: Color(0xFF182533),
    bubbleOut: Color(0xFF2B5278),
    bubbleInSelected: Color(0xFF2E70A5),
    bubbleOutSelected: Color(0xFF2E70A5),
    bubbleTextIn: Color(0xFFF5F5F5),
    bubbleTextOut: Color(0xFFE4ECF2),
    timeIn: Color(0xFF6D7F8F),
    timeOut: Color(0xFF7DA8D3),
    ticksOut: Color(0xFF6BBFFF),
    replyBarIn: Color(0xFF429BDB),
    replyBarOut: Color(0xFF65B9F4),
    serviceBg: Color(0xD5213040),
    serviceText: Color(0xFFFFFFFF),
    datePillBg: Color(0xD5213040),
    chatWallpaper: Color(0xFF0E1621),
  );

  /// Night palette with true-black surfaces for OLED screens.
  static const AppPalette amoled = AppPalette(
    windowBg: Color(0xFF000000),
    windowBgOver: Color(0xFF0B0B0C),
    windowBgRipple: Color(0xFF141415),
    accent: Color(0xFF5288C1),
    accentOver: Color(0xFF3476AB),
    accentRipple: Color(0xFF3B7CB1),
    onAccent: Color(0xFFFFFFFF),
    text: Color(0xFFF6F6F6),
    textSecondary: Color(0xFF828282),
    link: Color(0xFF6AB3F3),
    error: Color(0xFFDC3D3D),
    online: Color(0xFF63B6FF),
    icon: Color(0xFF7D7F81),
    iconActive: Color(0xFF6AB3F3),
    divider: Color(0xFF000000),
    topBarBg: Color(0xFF000000),
    composeBg: Color(0xFF1E1E1F),
    searchBg: Color(0xFF1E1E1E),
    searchHint: Color(0xFF6D7883),
    listRowHover: Color(0xFF161617),
    listRowSelected: Color(0xFF2B5278),
    listName: Color(0xFFF1F1F1),
    listNameSelected: Color(0xFFFFFFFF),
    listDate: Color(0xFF787878),
    listPreview: Color(0xFF828282),
    listSender: Color(0xFF73B9F5),
    badge: Color(0xFF399EF3),
    badgeMuted: Color(0xFF454545),
    badgeText: Color(0xFFFFFFFF),
    bubbleIn: Color(0xFF1F2123),
    bubbleOut: Color(0xFF366CAF),
    bubbleInSelected: Color(0xFF314A61),
    bubbleOutSelected: Color(0xFF4B7DAF),
    bubbleTextIn: Color(0xFFFAFAFA),
    bubbleTextOut: Color(0xFFFAFAFA),
    timeIn: Color(0xFF7D7F81),
    timeOut: Color(0xFF94D3F6),
    ticksOut: Color(0xFFFFFFFF),
    replyBarIn: Color(0xFF79C4FC),
    replyBarOut: Color(0xFF9FD9FF),
    serviceBg: Color(0x96373737),
    serviceText: Color(0xFFFFFFFF),
    datePillBg: Color(0x96373737),
    chatWallpaper: Color(0xFF0F0F10),
  );

  AppPalette withAccent(Color value) => copyWith(
        accent: value,
        accentOver: Color.lerp(value, const Color(0xFF000000), 0.08)!,
        accentRipple: Color.lerp(value, const Color(0xFF000000), 0.16)!,
        badge: value,
      );

  static AppPalette lerp(AppPalette a, AppPalette b, double t) => AppPalette(
        windowBg: Color.lerp(a.windowBg, b.windowBg, t)!,
        windowBgOver: Color.lerp(a.windowBgOver, b.windowBgOver, t)!,
        windowBgRipple: Color.lerp(a.windowBgRipple, b.windowBgRipple, t)!,
        accent: Color.lerp(a.accent, b.accent, t)!,
        accentOver: Color.lerp(a.accentOver, b.accentOver, t)!,
        accentRipple: Color.lerp(a.accentRipple, b.accentRipple, t)!,
        onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
        text: Color.lerp(a.text, b.text, t)!,
        textSecondary: Color.lerp(a.textSecondary, b.textSecondary, t)!,
        link: Color.lerp(a.link, b.link, t)!,
        error: Color.lerp(a.error, b.error, t)!,
        online: Color.lerp(a.online, b.online, t)!,
        icon: Color.lerp(a.icon, b.icon, t)!,
        iconActive: Color.lerp(a.iconActive, b.iconActive, t)!,
        divider: Color.lerp(a.divider, b.divider, t)!,
        topBarBg: Color.lerp(a.topBarBg, b.topBarBg, t)!,
        composeBg: Color.lerp(a.composeBg, b.composeBg, t)!,
        searchBg: Color.lerp(a.searchBg, b.searchBg, t)!,
        searchHint: Color.lerp(a.searchHint, b.searchHint, t)!,
        listRowHover: Color.lerp(a.listRowHover, b.listRowHover, t)!,
        listRowSelected: Color.lerp(a.listRowSelected, b.listRowSelected, t)!,
        listName: Color.lerp(a.listName, b.listName, t)!,
        listNameSelected: Color.lerp(a.listNameSelected, b.listNameSelected, t)!,
        listDate: Color.lerp(a.listDate, b.listDate, t)!,
        listPreview: Color.lerp(a.listPreview, b.listPreview, t)!,
        listSender: Color.lerp(a.listSender, b.listSender, t)!,
        badge: Color.lerp(a.badge, b.badge, t)!,
        badgeMuted: Color.lerp(a.badgeMuted, b.badgeMuted, t)!,
        badgeText: Color.lerp(a.badgeText, b.badgeText, t)!,
        bubbleIn: Color.lerp(a.bubbleIn, b.bubbleIn, t)!,
        bubbleOut: Color.lerp(a.bubbleOut, b.bubbleOut, t)!,
        bubbleInSelected: Color.lerp(a.bubbleInSelected, b.bubbleInSelected, t)!,
        bubbleOutSelected:
            Color.lerp(a.bubbleOutSelected, b.bubbleOutSelected, t)!,
        bubbleTextIn: Color.lerp(a.bubbleTextIn, b.bubbleTextIn, t)!,
        bubbleTextOut: Color.lerp(a.bubbleTextOut, b.bubbleTextOut, t)!,
        timeIn: Color.lerp(a.timeIn, b.timeIn, t)!,
        timeOut: Color.lerp(a.timeOut, b.timeOut, t)!,
        ticksOut: Color.lerp(a.ticksOut, b.ticksOut, t)!,
        replyBarIn: Color.lerp(a.replyBarIn, b.replyBarIn, t)!,
        replyBarOut: Color.lerp(a.replyBarOut, b.replyBarOut, t)!,
        serviceBg: Color.lerp(a.serviceBg, b.serviceBg, t)!,
        serviceText: Color.lerp(a.serviceText, b.serviceText, t)!,
        datePillBg: Color.lerp(a.datePillBg, b.datePillBg, t)!,
        chatWallpaper: Color.lerp(a.chatWallpaper, b.chatWallpaper, t)!,
      );

  AppPalette copyWith({
    Color? windowBg,
    Color? windowBgOver,
    Color? windowBgRipple,
    Color? accent,
    Color? accentOver,
    Color? accentRipple,
    Color? onAccent,
    Color? text,
    Color? textSecondary,
    Color? link,
    Color? error,
    Color? online,
    Color? icon,
    Color? iconActive,
    Color? divider,
    Color? topBarBg,
    Color? composeBg,
    Color? searchBg,
    Color? searchHint,
    Color? listRowHover,
    Color? listRowSelected,
    Color? listName,
    Color? listNameSelected,
    Color? listDate,
    Color? listPreview,
    Color? listSender,
    Color? badge,
    Color? badgeMuted,
    Color? badgeText,
    Color? bubbleIn,
    Color? bubbleOut,
    Color? bubbleInSelected,
    Color? bubbleOutSelected,
    Color? bubbleTextIn,
    Color? bubbleTextOut,
    Color? timeIn,
    Color? timeOut,
    Color? ticksOut,
    Color? replyBarIn,
    Color? replyBarOut,
    Color? serviceBg,
    Color? serviceText,
    Color? datePillBg,
    Color? chatWallpaper,
  }) {
    return AppPalette(
      windowBg: windowBg ?? this.windowBg,
      windowBgOver: windowBgOver ?? this.windowBgOver,
      windowBgRipple: windowBgRipple ?? this.windowBgRipple,
      accent: accent ?? this.accent,
      accentOver: accentOver ?? this.accentOver,
      accentRipple: accentRipple ?? this.accentRipple,
      onAccent: onAccent ?? this.onAccent,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      link: link ?? this.link,
      error: error ?? this.error,
      online: online ?? this.online,
      icon: icon ?? this.icon,
      iconActive: iconActive ?? this.iconActive,
      divider: divider ?? this.divider,
      topBarBg: topBarBg ?? this.topBarBg,
      composeBg: composeBg ?? this.composeBg,
      searchBg: searchBg ?? this.searchBg,
      searchHint: searchHint ?? this.searchHint,
      listRowHover: listRowHover ?? this.listRowHover,
      listRowSelected: listRowSelected ?? this.listRowSelected,
      listName: listName ?? this.listName,
      listNameSelected: listNameSelected ?? this.listNameSelected,
      listDate: listDate ?? this.listDate,
      listPreview: listPreview ?? this.listPreview,
      listSender: listSender ?? this.listSender,
      badge: badge ?? this.badge,
      badgeMuted: badgeMuted ?? this.badgeMuted,
      badgeText: badgeText ?? this.badgeText,
      bubbleIn: bubbleIn ?? this.bubbleIn,
      bubbleOut: bubbleOut ?? this.bubbleOut,
      bubbleInSelected: bubbleInSelected ?? this.bubbleInSelected,
      bubbleOutSelected: bubbleOutSelected ?? this.bubbleOutSelected,
      bubbleTextIn: bubbleTextIn ?? this.bubbleTextIn,
      bubbleTextOut: bubbleTextOut ?? this.bubbleTextOut,
      timeIn: timeIn ?? this.timeIn,
      timeOut: timeOut ?? this.timeOut,
      ticksOut: ticksOut ?? this.ticksOut,
      replyBarIn: replyBarIn ?? this.replyBarIn,
      replyBarOut: replyBarOut ?? this.replyBarOut,
      serviceBg: serviceBg ?? this.serviceBg,
      serviceText: serviceText ?? this.serviceText,
      datePillBg: datePillBg ?? this.datePillBg,
      chatWallpaper: chatWallpaper ?? this.chatWallpaper,
    );
  }
}
