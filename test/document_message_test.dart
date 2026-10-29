import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/models.dart';

import 'support/fake_chat_core.dart';

final _now = DateTime(2026, 10, 29, 12, 0);

List<MessageItem> _timeline(List<Map<String, dynamic>> raw) =>
    buildTimeline(raw, now: _now)
        .where((item) => !item.isDateSeparator)
        .toList();

void main() {
  test('a file item exposes the core document fields', () {
    final item = _timeline([
      documentItem(
        time: _now,
        fileName: 'quarterly-report.pdf',
        size: 524288,
        fileId: 7,
        fileStatus: 'rcvInvitation',
      ),
    ]).single;

    expect(item.isDocument, isTrue);
    expect(item.fileName, 'quarterly-report.pdf');
    expect(item.fileSize, 524288);
    expect(item.fileId, 7);
    expect(item.filePath, isNull);
    expect(item.transferStatus, 'rcvInvitation');
  });

  test('audio attachments keep their own row instead of a document card', () {
    final item = _timeline([
      documentItem(time: _now, fileName: 'song.mp3', size: 4096, fileId: 9),
    ]).single;

    expect(item.isDocument, isFalse);
    expect(item.fileName, isNull);
  });

  group('document bubble', () {
    Future<void> pumpDocument(
      WidgetTester tester,
      MessageItem message, {
      void Function(MessageItem message)? onDownloadFile,
      void Function(MessageItem message)? onOpenFile,
      Brightness brightness = Brightness.light,
    }) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final theme = buildAppTheme(const AppThemeSettings(), brightness);
      await tester.pumpWidget(
        AppThemeScope(
          theme: theme,
          child: MaterialApp(
            theme: theme.toMaterial(),
            home: Scaffold(
              body: ConversationPanel(
                chat: const ChatSummary(
                  id: '@1',
                  name: 'Alice',
                  preview: 'file',
                  time: '12:00',
                ),
                messages: [message],
                onDownloadFile: onDownloadFile,
                onOpenFile: onOpenFile,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    MessageItem document({
      String? filePath,
      String status = 'rcvInvitation',
      int? progress,
      int? total,
      String text = '',
      bool outgoing = false,
    }) => _timeline([
      documentItem(
        time: _now,
        fileName: 'quarterly-report.pdf',
        size: 524288,
        fileId: 7,
        fileStatus: status,
        progress: progress,
        total: total,
        filePath: filePath,
        text: text,
        fromMe: outgoing,
      ),
    ]).single;

    testWidgets('a pending download paints the card and the corner badge', (
      tester,
    ) async {
      var downloads = 0;
      var opens = 0;
      await pumpDocument(
        tester,
        document(),
        onDownloadFile: (_) => downloads++,
        onOpenFile: (_) => opens++,
      );

      expect(find.text('quarterly-report.pdf'), findsOneWidget);
      expect(find.text('512 KB'), findsOneWidget);
      expect(find.byKey(const ValueKey('document-download')), findsOneWidget);
      // Without a caption the time rides on the status line, like Telegram.
      expect(find.text('12:00'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('document-card')));
      await tester.pumpAndSettle();
      expect(downloads, 1);
      expect(opens, 0);
    });

    testWidgets('a downloaded file opens instead of downloading again', (
      tester,
    ) async {
      var downloads = 0;
      final opened = <String?>[];
      await pumpDocument(
        tester,
        document(status: 'rcvComplete', filePath: '/tmp/quarterly-report.pdf'),
        onDownloadFile: (_) => downloads++,
        onOpenFile: (message) => opened.add(message.filePath),
      );

      expect(find.byKey(const ValueKey('document-download')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('document-card')));
      await tester.pumpAndSettle();
      expect(opened, ['/tmp/quarterly-report.pdf']);
      expect(downloads, 0);
    });

    testWidgets('a running receive shows the radial and ignores taps', (
      tester,
    ) async {
      var downloads = 0;
      await pumpDocument(
        tester,
        document(
          status: 'rcvTransfer',
          progress: 131072,
          total: 524288,
        ),
        onDownloadFile: (_) => downloads++,
      );

      expect(find.text('128 KB / 512 KB'), findsOneWidget);
      final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(ring.value, closeTo(0.25, 1e-9));
      expect(find.byKey(const ValueKey('document-download')), findsNothing);
      expect(find.byKey(const ValueKey('document-card')), findsNothing);
      expect(downloads, 0);
    });

    testWidgets('a caption sits under the card and keeps the time once', (
      tester,
    ) async {
      await pumpDocument(
        tester,
        document(text: 'The numbers you asked for'),
      );

      expect(find.text('The numbers you asked for'), findsOneWidget);
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text('512 KB'), findsOneWidget);
    });

    testWidgets('reactions hang under the card without a second time row', (
      tester,
    ) async {
      final message = document().copyWith(
        reactions: const [
          MessageReaction(emoji: '👍', count: 2, mine: true),
        ],
      );
      await pumpDocument(tester, message);

      expect(find.byKey(const ValueKey('reaction-chip-👍')), findsOneWidget);
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text('512 KB'), findsOneWidget);
    });
  });
}
