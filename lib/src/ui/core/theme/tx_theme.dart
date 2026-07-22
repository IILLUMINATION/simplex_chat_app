import 'package:flutter/material.dart';

/// Форма бабблов сообщений
enum TxBubbleStyle {
  material3, // Округлые формы Material 3
  telegram,  // С острыми хвостиками снизу
  minimal,   // Прямоугольные с небольшим скруглением
}

/// Расширенная система тем для TangleX Chat
@immutable
class TxChatTheme extends ThemeExtension<TxChatTheme> {
  const TxChatTheme({
    required this.myBubbleBg,
    required this.myBubbleFg,
    required this.peerBubbleBg,
    required this.peerBubbleFg,
    required this.myBubbleGradient,
    required this.peerBubbleGradient,
    required this.chatBackground,
    required this.wallpaperPatternOpacity,
    required this.bubbleStyle,
    required this.bubbleRadius,
    required this.timeTextColor,
    required this.quoteBorderColor,
  });

  final Color myBubbleBg;
  final Color myBubbleFg;
  final Color peerBubbleBg;
  final Color peerBubbleFg;
  final Gradient? myBubbleGradient;
  final Gradient? peerBubbleGradient;
  final Color chatBackground;
  final double wallpaperPatternOpacity;
  final TxBubbleStyle bubbleStyle;
  final double bubbleRadius;
  final Color timeTextColor;
  final Color quoteBorderColor;

  /// Пресет: Telegram Dark / AMOLED со свежими фиолетовыми исходящими
  factory TxChatTheme.amoledDark() {
    return const TxChatTheme(
      myBubbleBg: Color(0xFF7636D6), // Яркий пурпурный/фиолетовый ТГ
      myBubbleFg: Colors.white,
      peerBubbleBg: Color(0xFF1E2C3A), // Тёмный сланцевый ТГ
      peerBubbleFg: Colors.white,
      myBubbleGradient: null,
      peerBubbleGradient: null,
      chatBackground: Color(0xFF0E1621), // Глубокий темный фон
      wallpaperPatternOpacity: 0.08,
      bubbleStyle: TxBubbleStyle.telegram,
      bubbleRadius: 16.0,
      timeTextColor: Color(0xBBFFFFFF),
      quoteBorderColor: Color(0xFF64B5F6),
    );
  }

  /// Пресет: Material 3 Dark (По умолчанию)
  factory TxChatTheme.m3Dark(ColorScheme cs) {
    return TxChatTheme(
      myBubbleBg: cs.primaryContainer,
      myBubbleFg: cs.onPrimaryContainer,
      peerBubbleBg: cs.surfaceContainerHighest,
      peerBubbleFg: cs.onSurface,
      myBubbleGradient: null,
      peerBubbleGradient: null,
      chatBackground: cs.surface,
      wallpaperPatternOpacity: 0.0,
      bubbleStyle: TxBubbleStyle.material3,
      bubbleRadius: 20.0,
      timeTextColor: cs.onSurfaceVariant.withValues(alpha: 0.8),
      quoteBorderColor: cs.primary,
    );
  }

  @override
  TxChatTheme copyWith({
    Color? myBubbleBg,
    Color? myBubbleFg,
    Color? peerBubbleBg,
    Color? peerBubbleFg,
    Gradient? myBubbleGradient,
    Gradient? peerBubbleGradient,
    Color? chatBackground,
    double? wallpaperPatternOpacity,
    TxBubbleStyle? bubbleStyle,
    double? bubbleRadius,
    Color? timeTextColor,
    Color? quoteBorderColor,
  }) {
    return TxChatTheme(
      myBubbleBg: myBubbleBg ?? this.myBubbleBg,
      myBubbleFg: myBubbleFg ?? this.myBubbleFg,
      peerBubbleBg: peerBubbleBg ?? this.peerBubbleBg,
      peerBubbleFg: peerBubbleFg ?? this.peerBubbleFg,
      myBubbleGradient: myBubbleGradient ?? this.myBubbleGradient,
      peerBubbleGradient: peerBubbleGradient ?? this.peerBubbleGradient,
      chatBackground: chatBackground ?? this.chatBackground,
      wallpaperPatternOpacity:
          wallpaperPatternOpacity ?? this.wallpaperPatternOpacity,
      bubbleStyle: bubbleStyle ?? this.bubbleStyle,
      bubbleRadius: bubbleRadius ?? this.bubbleRadius,
      timeTextColor: timeTextColor ?? this.timeTextColor,
      quoteBorderColor: quoteBorderColor ?? this.quoteBorderColor,
    );
  }

  @override
  TxChatTheme lerp(ThemeExtension<TxChatTheme>? other, double t) {
    if (other is! TxChatTheme) return this;
    return TxChatTheme(
      myBubbleBg: Color.lerp(myBubbleBg, other.myBubbleBg, t)!,
      myBubbleFg: Color.lerp(myBubbleFg, other.myBubbleFg, t)!,
      peerBubbleBg: Color.lerp(peerBubbleBg, other.peerBubbleBg, t)!,
      peerBubbleFg: Color.lerp(peerBubbleFg, other.peerBubbleFg, t)!,
      myBubbleGradient: Gradient.lerp(myBubbleGradient, other.myBubbleGradient, t),
      peerBubbleGradient: Gradient.lerp(peerBubbleGradient, other.peerBubbleGradient, t),
      chatBackground: Color.lerp(chatBackground, other.chatBackground, t)!,
      wallpaperPatternOpacity:
          Color.lerp(Colors.black, Colors.white, t)!.a, // stub lerp
      bubbleStyle: t < 0.5 ? bubbleStyle : other.bubbleStyle,
      bubbleRadius: (bubbleRadius + (other.bubbleRadius - bubbleRadius) * t),
      timeTextColor: Color.lerp(timeTextColor, other.timeTextColor, t)!,
      quoteBorderColor: Color.lerp(quoteBorderColor, other.quoteBorderColor, t)!,
    );
  }
}

/// Удобное расширение для получения темы из BuildContext
extension TxThemeContext on BuildContext {
  TxChatTheme get txTheme =>
      Theme.of(this).extension<TxChatTheme>() ??
      TxChatTheme.m3Dark(Theme.of(this).colorScheme);
}
