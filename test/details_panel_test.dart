import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/details_panel.dart';
import 'package:tanglex_chat/src/shell/models.dart';

Future<void> _pumpPanel(
  WidgetTester tester,
  ChatSummary chat, {
  Size surface = const Size(1440, 900),
  double panelWidth = 360,
  VoidCallback? onToggleMute,
  VoidCallback? onSearch,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final theme = buildAppTheme(
    const AppThemeSettings(fontFamily: 'Roboto'),
    Brightness.light,
  );
  await tester.pumpWidget(
    AppThemeScope(
      theme: theme,
      child: MaterialApp(
        theme: theme.toMaterial(),
        home: Scaffold(
          body: SizedBox(
            width: panelWidth,
            height: surface.height,
            child: DetailsPanel(
              chat: chat,
              onClose: () {},
              onToggleMute: onToggleMute,
              onSearch: onSearch,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('profile panel shows the SimpleX profile keys as Telegram rows', (
    tester,
  ) async {
    const chat = ChatSummary(
      id: '@1',
      name: 'Alice Bergström',
      preview: 'Sent you the room keys',
      time: '14:32',
      subtitle: 'connected',
      canSend: true,
      fullName: 'Alice B. Smith',
      bio: 'Keys, coffee and long walks',
      quantumResistant: true,
    );

    await _pumpPanel(tester, chat);

    expect(find.text('Alice Bergström'), findsWidgets);
    expect(find.text('connected'), findsOneWidget);
    expect(find.text('Bio'), findsOneWidget);
    expect(find.text('Keys, coffee and long walks'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Alice B. Smith'), findsOneWidget);
    expect(find.text('E2E encryption'), findsOneWidget);
    expect(find.text('Quantum resistant'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    // Desktop third column: close button, no back arrow.
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);

    // The core's local name is an implementation detail, not profile data.
    expect(find.textContaining('SimpleX chat reference'), findsNothing);
    expect(find.textContaining('alice'), findsNothing);
  });

  testWidgets('a muted group lists its members and greys the switch', (
    tester,
  ) async {
    var toggles = 0;
    const chat = ChatSummary(
      id: '#7',
      name: 'Meander Dev',
      preview: 'pushed the FFI bridge',
      time: '13:05',
      isGroup: true,
      muted: true,
      memberCount: 12,
      bio: 'Build logs for TangleX',
    );

    await _pumpPanel(tester, chat, onToggleMute: () => toggles++);

    expect(find.text('Meander Dev'), findsWidgets);
    expect(find.text('12 members'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Build logs for TangleX'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(toggles, 1);
  });

  testWidgets('a narrow layout uses the centred Telegram Android cover', (
    tester,
  ) async {
    const chat = ChatSummary(
      id: '@1',
      name: 'Alice',
      preview: 'hi',
      time: '14:32',
      subtitle: 'connected',
      needsAccept: true,
      canSend: false,
    );

    await _pumpPanel(
      tester,
      chat,
      surface: const Size(420, 800),
      panelWidth: 420,
    );

    expect(find.text('contact request'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });
}
