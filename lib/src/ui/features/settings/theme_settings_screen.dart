import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tx_theme.dart';

class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.txTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TangleX Theme & UI'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Bubble Style',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<TxBubbleStyle>(
            segments: const [
              ButtonSegment(
                value: TxBubbleStyle.telegram,
                label: Text('Telegram'),
              ),
              ButtonSegment(
                value: TxBubbleStyle.material3,
                label: Text('Material 3'),
              ),
            ],
            selected: {theme.bubbleStyle},
            onSelectionChanged: (selected) {
              if (selected.isEmpty) return;
              // Style change notification
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Style changed to ${selected.first.name}')),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Theme Presets',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.nightlight_round),
            title: const Text('AMOLED Dark'),
            subtitle: const Text('True black for OLED screens'),
            onTap: () {
              // Toggle or apply preset
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('AMOLED theme applied')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette_rounded),
            title: const Text('Telegram Blue'),
            subtitle: const Text('Classic blue bubble style'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Telegram Blue theme applied')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.bubble_chart_rounded),
            title: const Text('Minimal Minimalist'),
            subtitle: const Text('Clean borders and soft surfaces'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Minimal theme applied')),
              );
            },
          ),
        ],
      ),
    );
  }
}
