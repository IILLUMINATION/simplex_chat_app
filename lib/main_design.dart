import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/design/app_theme.dart';
import 'src/design/app_theme_controller.dart';
import 'src/shell/messenger_shell.dart';

/// Shell entry: adaptive TangleX UI backed by the real SimpleX core.
/// `flutter run -t lib/main_design.dart`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: DesignPreviewApp()));
}

class DesignPreviewApp extends ConsumerWidget {
  const DesignPreviewApp({super.key});

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
      home: const MessengerShell(),
    );
  }
}
