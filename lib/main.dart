import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/design/app_theme.dart';
import 'src/design/app_theme_controller.dart';
import 'src/shell/messenger_shell.dart';
import 'src/shell/window_chrome.dart';

/// TangleX entry: the adaptive Telegram-style shell backed by the SimpleX core.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: TangleXApp()));
}

class TangleXApp extends ConsumerWidget {
  const TangleXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appThemeProvider);
    final light = ref.watch(appThemeLightProvider);
    final dark = ref.watch(appThemeDarkProvider);

    return MaterialApp(
      title: 'TangleX',
      debugShowCheckedModeBanner: false,
      theme: light.toMaterial(),
      darkTheme: dark.toMaterial(),
      themeMode: settings.mode,
      builder: (context, child) {
        final platform = MediaQuery.platformBrightnessOf(context);
        final brightness = switch (settings.mode) {
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
          ThemeMode.system => platform,
        };
        return AppThemeScope(
          theme: brightness == Brightness.dark ? dark : light,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const WindowChrome(child: MessengerShell()),
    );
  }
}
