import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_palette.dart';
import '../design/app_theme.dart';
import '../design/app_theme_controller.dart';

/// Connects [AppearanceScreen] to the persisted theme controller.
class AppearanceScreenHost extends ConsumerWidget {
  const AppearanceScreenHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appThemeProvider);
    final controller = ref.read(appThemeProvider.notifier);
    return AppearanceScreen(settings: settings, onChanged: controller.update);
  }
}

/// Telegram-style appearance editor: theme presets, accents, bubble colors,
/// wallpaper, corner radius and text size. Every control writes a full
/// [AppThemeSettings], which the controller persists and rebuilds from.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final AppThemeSettings settings;
  final ValueChanged<AppThemeSettings> onChanged;

  void _apply(AppThemeSettings next) => onChanged(next);

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final m = theme.metrics;

    return Material(
      color: p.windowBg,
      child: Column(
        children: [
          SizedBox(
            height: m.topBarHeight,
            child: Row(
              children: [
                const SizedBox(width: 4),
                _IconAction(
                  icon: Icons.arrow_back,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Appearance',
                    style: theme.typography.chatTitle.copyWith(color: p.text),
                  ),
                ),
                TextButton(
                  onPressed: () => _apply(const AppThemeSettings()),
                  style: TextButton.styleFrom(
                    foregroundColor: p.accent,
                    textStyle: theme.typography.button,
                  ),
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Container(height: 1, color: p.divider),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                final controls = _Controls(
                  settings: settings,
                  onChanged: _apply,
                );
                if (!wide) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: SizedBox(height: 250, child: ChatPreview(theme)),
                      ),
                      Expanded(child: controls),
                    ],
                  );
                }
                return Row(
                  children: [
                    SizedBox(width: 420, child: controls),
                    Container(width: 1, color: p.divider),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: ChatPreview(theme),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Controls =====

class _Controls extends StatelessWidget {
  const _Controls({required this.settings, required this.onChanged});

  final AppThemeSettings settings;
  final ValueChanged<AppThemeSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Theme'),
          _ThemeGrid(settings: settings, onChanged: onChanged),
          const SizedBox(height: 20),
          _SectionTitle('Accent'),
          _AccentRow(settings: settings, onChanged: onChanged),
          const SizedBox(height: 20),
          _SectionTitle('Chat background'),
          _WallpaperRow(settings: settings, onChanged: onChanged),
          const SizedBox(height: 20),
          _SectionTitle('Message bubbles'),
          _BubbleColors(settings: settings, onChanged: onChanged),
          const SizedBox(height: 20),
          _SectionTitle('Corner radius'),
          _RadiusSlider(settings: settings, onChanged: onChanged),
          const SizedBox(height: 16),
          _SectionTitle('Text size'),
          _FontSlider(settings: settings, onChanged: onChanged),
          const SizedBox(height: 16),
          Text(
            'Changes apply instantly and are saved on this device.',
            style: theme.typography.listPreview.copyWith(
              color: p.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: theme.typography.sectionHeader.copyWith(
          color: theme.palette.textSecondary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

const _themeChoices = <({String label, AppThemePreset preset, ThemeMode mode})>[
  (label: 'Day', preset: AppThemePreset.classic, mode: ThemeMode.light),
  (label: 'Day Blue', preset: AppThemePreset.blue, mode: ThemeMode.light),
  (label: 'Night', preset: AppThemePreset.classic, mode: ThemeMode.dark),
  (label: 'Midnight', preset: AppThemePreset.amoled, mode: ThemeMode.dark),
];

class _ThemeGrid extends StatelessWidget {
  const _ThemeGrid({required this.settings, required this.onChanged});

  final AppThemeSettings settings;
  final ValueChanged<AppThemeSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    bool isSelected(({String label, AppThemePreset preset, ThemeMode mode}) c) {
      if (settings.preset != c.preset) return false;
      if (settings.mode == ThemeMode.system) {
        return dark == (c.mode == ThemeMode.dark);
      }
      return settings.mode == c.mode;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final choice in _themeChoices)
              SizedBox(
                width: cardWidth,
                child: _ThemeCard(
                  label: choice.label,
                  selected: isSelected(choice),
                  palette: buildAppTheme(
                    AppThemeSettings(preset: choice.preset),
                    choice.mode == ThemeMode.dark
                        ? Brightness.dark
                        : Brightness.light,
                  ).palette,
                  onTap: () => onChanged(
                    settings.copyWith(preset: choice.preset, mode: choice.mode),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: theme.motion.universal,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: palette.chatWallpaper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? p.accent : p.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MiniBubble(color: palette.bubbleIn, width: 52),
                const SizedBox(width: 6),
                _MiniBubble(color: palette.bubbleOut, width: 64),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.typography.listName.copyWith(
                      color: palette.text,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, size: 16, color: p.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBubble extends StatelessWidget {
  const _MiniBubble({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x33000000)),
      ),
    );
  }
}

const _accents = <Color>[
  Color(0xFF40A7E3),
  Color(0xFF4DC920),
  Color(0xFF26C6B0),
  Color(0xFFF2A03D),
  Color(0xFFEE5A5A),
  Color(0xFF9B6DD6),
  Color(0xFFE85A9B),
  Color(0xFF8C9BAB),
];

class _AccentRow extends StatelessWidget {
  const _AccentRow({required this.settings, required this.onChanged});

  final AppThemeSettings settings;
  final ValueChanged<AppThemeSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: [
        _Swatch(
          color: p.accent,
          selected: settings.accent == null,
          icon: Icons.auto_awesome,
          onTap: () => onChanged(settings.copyWith(clearAccent: true)),
        ),
        for (final accent in _accents)
          _Swatch(
            color: accent,
            selected: settings.accent == accent,
            onTap: () => onChanged(settings.copyWith(accent: accent)),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? p.accent : p.divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: selected || icon != null
              ? Icon(icon ?? Icons.check, size: 16, color: _onColor(color))
              : null,
        ),
      ),
    );
  }

  static Color _onColor(Color bg) =>
      bg.computeLuminance() > 0.55 ? const Color(0xFF222222) : Colors.white;
}

const _wallpapers = <Color?>[
  null,
  Color(0xFFF2F5F7),
  Color(0xFFE8EEF3),
  Color(0xFFF5EFE6),
  Color(0xFF0E1621),
  Color(0xFF17212B),
  Color(0xFF0F0F10),
];

class _WallpaperRow extends StatelessWidget {
  const _WallpaperRow({required this.settings, required this.onChanged});

  final AppThemeSettings settings;
  final ValueChanged<AppThemeSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final wp in _wallpapers)
          Semantics(
            button: true,
            selected: settings.wallpaper == wp,
            child: InkWell(
              onTap: () => onChanged(
                wp == null
                    ? settings.copyWith(clearWallpaper: true)
                    : settings.copyWith(wallpaper: wp),
              ),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 42,
                height: 36,
                decoration: BoxDecoration(
                  color: wp ?? p.chatWallpaper,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: settings.wallpaper == wp ? p.accent : p.divider,
                    width: settings.wallpaper == wp ? 2 : 1,
                  ),
                ),
                child: wp == null
                    ? Icon(Icons.block, size: 16, color: p.icon)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

const _inBubbles = <Color?>[
  null,
  Color(0xFFFFFFFF),
  Color(0xFFF1F1F1),
  Color(0xFFE9F0F5),
  Color(0xFFF7F0E3),
  Color(0xFF182533),
];

const _outBubbles = <Color?>[
  null,
  Color(0xFFEFFDDE),
  Color(0xFFDEF1FD),
  Color(0xFFD9F5EF),
  Color(0xFFF0E4FF),
  Color(0xFFFFF3C4),
];

class _BubbleColors extends StatelessWidget {
  const _BubbleColors({required this.settings, required this.onChanged});

  final AppThemeSettings settings;
  final ValueChanged<AppThemeSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Incoming',
          style: theme.typography.listPreview.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in _inBubbles)
              _BubbleSwatch(
                color: color ?? p.bubbleIn,
                isDefault: color == null,
                selected: settings.bubbleIn == color,
                outline: p.divider,
                accent: p.accent,
                onTap: () => onChanged(
                  color == null
                      ? settings.copyWith(clearBubbleIn: true)
                      : settings.copyWith(bubbleIn: color),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Outgoing',
          style: theme.typography.listPreview.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in _outBubbles)
              _BubbleSwatch(
                color: color ?? p.bubbleOut,
                isDefault: color == null,
                selected: settings.bubbleOut == color,
                outline: p.divider,
                accent: p.accent,
                onTap: () => onChanged(
                  color == null
                      ? settings.copyWith(clearBubbleOut: true)
                      : settings.copyWith(bubbleOut: color),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BubbleSwatch extends StatelessWidget {
  const _BubbleSwatch({
    required this.color,
    required this.selected,
    required this.isDefault,
    required this.outline,
    required this.accent,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final bool isDefault;
  final Color outline;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 46,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accent : outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 16, color: _Swatch._onColor(color))
              : (isDefault
                    ? Icon(Icons.auto_awesome, size: 12, color: outline)
                    : null),
        ),
      ),
    );
  }
}

class _RadiusSlider extends StatelessWidget {
  const _RadiusSlider({required this.settings, required this.onChanged});

  final AppThemeSettings settings;
  final ValueChanged<AppThemeSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.chat_bubble_outline, size: 16, color: p.icon),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _AccentSlider(
                  value: settings.bubbleRadius,
                  min: AppThemeSettings.minBubbleRadius,
                  max: AppThemeSettings.maxBubbleRadius,
                  divisions: 20,
                  onChanged: (v) =>
                      onChanged(settings.copyWith(bubbleRadius: v)),
                ),
              ),
            ),
            Icon(Icons.chat_bubble, size: 16, color: p.icon),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${settings.bubbleRadius.round()} px',
            style: theme.typography.listTime.copyWith(color: p.textSecondary),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RadiusSample(
              radius: settings.bubbleRadius,
              color: p.bubbleIn,
              textColor: p.bubbleTextIn,
            ),
            const SizedBox(width: 8),
            _RadiusSample(
              radius: settings.bubbleRadius,
              color: p.bubbleOut,
              textColor: p.bubbleTextOut,
            ),
          ],
        ),
      ],
    );
  }
}

class _RadiusSample extends StatelessWidget {
  const _RadiusSample({
    required this.radius,
    required this.color,
    required this.textColor,
  });

  final double radius;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        'Message',
        style: theme.typography.message.copyWith(color: textColor),
      ),
    );
  }
}

class _FontSlider extends StatelessWidget {
  const _FontSlider({required this.settings, required this.onChanged});

  final AppThemeSettings settings;
  final ValueChanged<AppThemeSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'A',
              style: TextStyle(
                fontFamily: theme.typography.messageMeta.fontFamily,
                fontSize: 14,
                color: p.icon,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _AccentSlider(
                  value: settings.fontScale,
                  min: AppThemeSettings.minFontScale,
                  max: AppThemeSettings.maxFontScale,
                  divisions: 10,
                  onChanged: (v) => onChanged(settings.copyWith(fontScale: v)),
                ),
              ),
            ),
            Text(
              'A',
              style: TextStyle(
                fontFamily: theme.typography.chatTitle.fontFamily,
                fontSize: 20,
                color: p.icon,
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${(settings.fontScale * 100).round()}%',
            style: theme.typography.listTime.copyWith(color: p.textSecondary),
          ),
        ),
        Text(
          'The quick brown fox jumps over the lazy dog',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.typography.message.copyWith(color: p.text),
        ),
      ],
    );
  }
}

class _AccentSlider extends StatelessWidget {
  const _AccentSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: p.accent,
        inactiveTrackColor: p.windowBgOver,
        thumbColor: p.accent,
        overlayColor: p.accent.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      hoverColor: theme.palette.windowBgOver,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          size: theme.metrics.iconSize,
          color: theme.palette.icon,
        ),
      ),
    );
  }
}

// ===== Live preview =====

/// Mini conversation that mirrors the edited settings, like Telegram's
/// preview strip above the theme controls.
class ChatPreview extends StatelessWidget {
  const ChatPreview(this.theme, {super.key});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final t = theme.typography;
    final m = theme.metrics;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.chatWallpaper,
          border: Border.all(color: p.divider),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                      decoration: BoxDecoration(
                        color: p.datePillBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Today',
                        style: t.service.copyWith(color: p.serviceText),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _PreviewBubble(
                        theme: theme,
                        outgoing: false,
                        text:
                            'This is how your chat looks with the new colors.',
                        meta: '14:20',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _PreviewBubble(
                        theme: theme,
                        outgoing: true,
                        text: 'Accent, bubble colors, radius, font — all live.',
                        meta: '14:21',
                        ticks: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              height: m.composeBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: p.composeBg,
              child: Row(
                children: [
                  Icon(
                    Icons.attach_file,
                    size: m.iconSize * 0.9,
                    color: p.icon,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: p.windowBgOver,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Text(
                        'Message',
                        style: t.input.copyWith(color: p.searchHint),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: p.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.send, size: 16, color: p.onAccent),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({
    required this.theme,
    required this.outgoing,
    required this.text,
    required this.meta,
    this.ticks = false,
  });

  final AppTheme theme;
  final bool outgoing;
  final String text;
  final String meta;
  final bool ticks;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final t = theme.typography;
    final m = theme.metrics;
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          padding: m.bubblePadding,
          decoration: BoxDecoration(
            color: outgoing ? p.bubbleOut : p.bubbleIn,
            borderRadius: BorderRadius.circular(m.bubbleRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: t.message.copyWith(
                  color: outgoing ? p.bubbleTextOut : p.bubbleTextIn,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    meta,
                    style: t.messageMeta.copyWith(
                      color: outgoing ? p.timeOut : p.timeIn,
                    ),
                  ),
                  if (ticks) ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.done_all,
                      size: 13,
                      color: outgoing ? p.ticksOut : p.timeIn,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
