// Standard buttons for TangleX.
//
// Use [AppPrimaryButton] for filled accent actions (Send, Connect, Save).
// Use [AppOutlinedButton] for secondary actions (Cancel, Reject).
// Use [AppIconButton] for round icon-only buttons (compose bar actions).

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.textOnAccent,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppIconSize.small),
                const SizedBox(width: AppSpacing.s2),
              ],
              Text(label),
            ],
          );

    final button = FilledButton(
      onPressed: loading ? null : onPressed,
      child: child,
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class AppOutlinedButton extends StatelessWidget {
  const AppOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : AppColors.textPrimary;
    final btn = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(
          color: destructive
              ? AppColors.error.withValues(alpha: 0.6)
              : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppIconSize.small, color: color),
            const SizedBox(width: AppSpacing.s2),
          ],
          Text(label),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Round icon-only button for compose bars and inline actions.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 40,
    this.iconSize = AppIconSize.regular,
    this.backgroundColor,
    this.foregroundColor,
    this.onLongPress,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Colors.transparent;
    final fg = foregroundColor ?? AppColors.textPrimary;
    final hasBg = bg.a != 0;

    final btn = Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        onLongPress: onLongPress,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: fg),
        ),
      ),
    );

    final wrapped = hasBg ? btn : btn;
    if (tooltip == null) return wrapped;
    return Tooltip(message: tooltip!, child: wrapped);
  }
}

/// Larger circular call-to-action used for "Send" in chat compose bar.
class AppSendButton extends StatelessWidget {
  const AppSendButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.onLongPress,
    this.tooltip,
    this.size = 44,
    this.iconSize = AppIconSize.regular,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: AppColors.accent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        onLongPress: onLongPress,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: AppColors.textOnAccent),
        ),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

/// Small label-style chip / pill button (used e.g. in incoming request tile).
class AppPillButton extends StatelessWidget {
  const AppPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.foreground,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.accent;
    final fg = foreground ?? AppColors.textOnAccent;
    return Material(
      color: bg,
      borderRadius: AppRadius.brs,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.brs,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppIconSize.small, color: fg),
                const SizedBox(width: AppSpacing.s1),
              ],
              Text(
                label,
                style: AppText.captionEmph.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
