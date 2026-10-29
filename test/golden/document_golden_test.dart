import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/models.dart';

import '../support/test_fonts.dart';

AppTheme _theme(Brightness brightness) =>
    buildAppTheme(const AppThemeSettings(fontFamily: 'Roboto'), brightness);

final _now = DateTime(2026, 10, 29, 12, 0);

MessageItem _document({
  required String name,
  required int size,
  required String time,
  required bool outgoing,
  String status = 'rcvInvitation',
  int? progress,
  int? total,
  String? path,
  String caption = '',
  List<MessageReaction> reactions = const [],
}) => MessageItem(
  text: caption,
  time: time,
  timestamp: _now,
  outgoing: outgoing,
  sender: outgoing ? null : 'Alice',
  itemId: time.hashCode,
  fileName: name,
  fileSize: size,
  fileId: 7,
  filePath: path,
  transferStatus: status,
  transferProgress: progress,
  transferTotal: total,
  reactions: reactions,
);

Widget _harness(Brightness brightness) {
  final theme = _theme(brightness);
  return AppThemeScope(
    theme: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.toMaterial(),
      home: Scaffold(
        body: ConversationPanel(
          chat: const ChatSummary(
            id: '@1',
            name: 'Alice',
            preview: 'Files',
            time: '12:04',
          ),
          messages: [
            MessageItem(text: 'Today', time: '', isDateSeparator: true),
            _document(
              name: 'quarterly-report-2026-final.pdf',
              size: 2489344,
              time: '12:01',
              outgoing: false,
            ),
            _document(
              name: 'database-dump.zip',
              size: 18432000,
              time: '12:02',
              outgoing: true,
              status: 'sndComplete',
              path: '/tmp/database-dump.zip',
              caption: 'Latest dump, no passwords inside',
            ),
            _document(
              name: 'IMG_20261029_113355.jpg',
              size: 7340032,
              time: '12:03',
              outgoing: false,
              status: 'rcvTransfer',
              progress: 4194304,
              total: 7340032,
            ),
            _document(
              name: 'notes.md',
              size: 2048,
              time: '12:04',
              outgoing: true,
              status: 'sndComplete',
              path: '/tmp/notes.md',
              reactions: const [
                MessageReaction(emoji: '👍', count: 2, mine: true),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('desktop document bubbles light', (tester) async {
    await _setSize(tester, const Size(900, 900));
    await tester.pumpWidget(_harness(Brightness.light));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ConversationPanel),
      matchesGoldenFile('goldens/document_desktop_light.png'),
    );
  });

  testWidgets('phone document bubbles dark', (tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(_harness(Brightness.dark));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ConversationPanel),
      matchesGoldenFile('goldens/document_phone_dark.png'),
    );
  });
}
