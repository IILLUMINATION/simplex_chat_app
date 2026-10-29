import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/window_chrome.dart';

final _theme = buildAppTheme(
  const AppThemeSettings(fontFamily: 'Roboto'),
  Brightness.dark,
);

Widget _app(Widget child) {
  return AppThemeScope(
    theme: _theme,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  const channel = MethodChannel('tanglex/window');

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'isMaximized') return false;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    WindowChromeController.instance.maximized.value = false;
  });

  Future<void> pumpChrome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(const WindowChrome(child: ColoredBox(color: Color(0xFF123456)))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the title strip is 24px tall and follows the palette', (
    tester,
  ) async {
    await pumpChrome(tester);
    final strip = find.byWidgetPredicate(
      (widget) =>
          widget is ColoredBox &&
          widget.color == _theme.palette.searchBg,
    );
    expect(strip, findsOneWidget);
    expect(tester.getSize(strip).height, 24);
  });

  testWidgets('window buttons drive the native window', (tester) async {
    await pumpChrome(tester);
    await tester.tap(find.byTooltip('Minimize'));
    await tester.tap(find.byTooltip('Maximize'));
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(
      calls.map((call) => call.method),
      containsAllInOrder(<String>['minimize', 'toggleMaximize', 'close']),
    );
  });

  testWidgets('a native maximize event swaps the glyph to restore', (
    tester,
  ) async {
    await pumpChrome(tester);
    expect(find.byTooltip('Maximize'), findsOneWidget);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'tanglex/window',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('state', <String, Object?>{'maximized': true}),
          ),
          (_) {},
        );
    await tester.pump();
    expect(find.byTooltip('Restore'), findsOneWidget);
    await tester.tap(find.byTooltip('Restore'));
    await tester.pump();
    expect(calls.map((call) => call.method), contains('toggleMaximize'));
  });

  testWidgets('double-clicking the strip maximizes the window', (
    tester,
  ) async {
    await pumpChrome(tester);
    const point = Offset(300, 12);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls.map((call) => call.method), contains('toggleMaximize'));
  });

  testWidgets('window edges start a native resize', (tester) async {
    await pumpChrome(tester);
    await tester.tapAt(const Offset(3, 3));
    await tester.pump();
    final resize = calls.where((call) => call.method == 'startResize').single;
    expect((resize.arguments as Map)['edge'], 0);
    await tester.tapAt(const Offset(998, 350));
    await tester.pump();
    final right = calls.where((call) => call.method == 'startResize').last;
    expect((right.arguments as Map)['edge'], WindowResizeEdge.right.index);
  });
}
