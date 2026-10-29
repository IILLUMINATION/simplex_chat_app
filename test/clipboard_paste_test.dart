import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/providers/persistent_store.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/messenger_shell.dart';
import 'package:tanglex_chat/src/shell/models.dart';

import 'support/fake_chat_core.dart';

const _clipboard = MethodChannel('tanglex/clipboard');

final _now = DateTime(2026, 10, 29, 12, 0);

Uint8List _pngBytes() {
  final image = img.Image(width: 24, height: 24);
  img.fill(image, color: img.ColorRgb8(64, 132, 198));
  return Uint8List.fromList(img.encodePng(image));
}

ChatPreview _direct(String ref, String name) => ChatPreview(
  chatRef: ref,
  chatType: 'contact',
  displayName: name,
  contactStatus: 'active',
  connStatusType: 'ready',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory dir;
  late File photo;
  late File document;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tanglex-paste');
    photo = File('${dir.path}/photo.png')
      ..writeAsBytesSync(_pngBytes());
    document = File('${dir.path}/quarterly-report.pdf')
      ..writeAsBytesSync(List<int>.filled(2048, 7));
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return null;
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_clipboard, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    dir.deleteSync(recursive: true);
  });

  void respondWithPaths(List<String> paths) {
    messenger.setMockMethodCallHandler(_clipboard, (call) async {
      if (call.method != 'readFiles') return null;
      return {'paths': paths, 'imagePath': null};
    });
  }

  void respondWithText(String text) {
    messenger.setMockMethodCallHandler(_clipboard, (call) async {
      if (call.method != 'readFiles') return null;
      return {'paths': <String>[], 'imagePath': null};
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': text};
      return null;
    });
  }

  Future<void> pumpComposer(
    WidgetTester tester, {
    void Function(
      List<ComposerAttachment> attachments,
      String text, {
      int? quotedItemId,
    })?
    onSendAttachments,
    void Function(String text, {int? quotedItemId, MessageReply? reply})?
    onSend,
    Size size = const Size(900, 700),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
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
            body: ConversationPanel(
              chat: const ChatSummary(
                id: '@1',
                name: 'Alice',
                preview: 'hi',
                time: '12:00',
              ),
              messages: const [],
              onSend: onSend,
              onSendAttachments: onSendAttachments,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressCtrlV(WidgetTester tester, {Finder? field}) async {
    await tester.tap(field ?? find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('pasting stages photos and documents until the send button', (
    tester,
  ) async {
    respondWithPaths([photo.path, document.path]);
    List<ComposerAttachment>? sent;
    String? caption;
    await pumpComposer(
      tester,
      onSendAttachments: (attachments, text, {int? quotedItemId}) {
        sent = attachments;
        caption = text;
      },
    );

    await pressCtrlV(tester);

    expect(find.byKey(const ValueKey('staged-attachment-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('staged-attachment-1')), findsOneWidget);
    expect(find.text('quarterly-report.pdf'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('staged-attachment-0')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Look at this');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(
      sent!.map((attachment) => attachment.name),
      ['photo.png', 'quarterly-report.pdf'],
    );
    expect(sent!.first.isImage, isTrue);
    expect(sent!.first.previewBytes, isNotNull);
    expect(sent!.last.isImage, isFalse);
    expect(caption, 'Look at this');
    expect(find.byKey(const ValueKey('staged-attachment-0')), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('a clipboard without files still pastes plain text', (
    tester,
  ) async {
    respondWithText('hello from the clipboard');
    await pumpComposer(tester);

    await pressCtrlV(tester);

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'hello from the clipboard',
    );
    expect(find.byKey(const ValueKey('staged-attachment-0')), findsNothing);
  });

  testWidgets('the attach menu offers the same paste action', (tester) async {
    respondWithPaths([photo.path]);
    await pumpComposer(tester);

    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('staged-attachment-0')), findsOneWidget);
  });

  testWidgets('Enter sends staged media without a caption', (tester) async {
    respondWithPaths([photo.path]);
    List<ComposerAttachment>? sent;
    String? caption;
    await pumpComposer(
      tester,
      onSendAttachments: (attachments, text, {int? quotedItemId}) {
        sent = attachments;
        caption = text;
      },
    );

    await pressCtrlV(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(caption, isEmpty);
    expect(find.byKey(const ValueKey('staged-attachment-0')), findsNothing);
  });

  testWidgets('the delete badge drops a staged attachment', (tester) async {
    respondWithPaths([photo.path, document.path]);
    await pumpComposer(tester);

    await pressCtrlV(tester);
    await tester.tap(find.byKey(const ValueKey('staged-remove-0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('staged-attachment-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('staged-attachment-1')), findsNothing);
    expect(find.text('quarterly-report.pdf'), findsOneWidget);
  });

  testWidgets('an undecodable image stays a document', (tester) async {
    final broken = File('${dir.path}/broken.png')
      ..writeAsBytesSync(List<int>.filled(64, 3));
    respondWithPaths([broken.path]);
    await pumpComposer(tester);

    await pressCtrlV(tester);

    expect(find.text('broken.png'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('staged-attachment-0')),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
  });

  testWidgets('pasting the same file twice stages it once', (tester) async {
    respondWithPaths([photo.path, photo.path]);
    await pumpComposer(tester);

    await pressCtrlV(tester);
    expect(find.byKey(const ValueKey('staged-attachment-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('staged-attachment-1')), findsNothing);

    await pressCtrlV(tester);
    expect(find.byKey(const ValueKey('staged-attachment-1')), findsNothing);
  });

  group('shell send', () {
    Widget app(FakeChatCore core) {
      final theme = buildAppTheme(
        const AppThemeSettings(fontFamily: 'Roboto'),
        Brightness.light,
      );
      return ProviderScope(
        overrides: [
          chatCoreProvider.overrideWithValue(core),
          clockProvider.overrideWithValue(() => _now),
        ],
        child: AppThemeScope(
          theme: theme,
          child: MaterialApp(
            theme: theme.toMaterial(),
            home: const MessengerShell(),
          ),
        ),
      );
    }

    Future<FakeChatCore> openChat(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final core = FakeChatCore(
        chats: [_direct('@1', 'Alice')],
        messages: {'@1': []},
        now: _now,
      );
      await tester.pumpWidget(app(core));
      await tester.pumpAndSettle();
      return core;
    }

    testWidgets('photos leave as an album with the caption on the first one', (
      tester,
    ) async {
      respondWithPaths([photo.path, document.path]);
      final core = await openChat(tester);
      final field = find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.byType(TextField),
      );

      await pressCtrlV(tester, field: field);
      await tester.enterText(field, 'Quarterly');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(core.sentImagePaths, [photo.path]);
      expect(core.sentImageCaptions, ['Quarterly']);
      expect(core.sentFiles, [document.path]);
      expect(core.sentFileCaptions, ['']);
    });

    testWidgets('a reply header rides on the first pasted item', (tester) async {
      respondWithPaths([photo.path, document.path]);
      final core = FakeChatCore(
        chats: [_direct('@1', 'Alice')],
        messages: {
          '@1': [textItem(text: 'original', time: _now)],
        },
        now: _now,
      );
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(core));
      await tester.pumpAndSettle();

      await tester.tap(find.text('original'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();

      final field = find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.byType(TextField),
      );
      await pressCtrlV(tester, field: field);
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      final quotedId =
          (core.messages['@1']!.first['meta'] as Map<String, dynamic>)['itemId'];
      expect(core.sentQuotedIds, [quotedId, null]);
      expect(find.text('original'), findsOneWidget);
    });

    testWidgets('documents keep the caption when no photo is pasted', (
      tester,
    ) async {
      respondWithPaths([document.path]);
      final core = await openChat(tester);
      final field = find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.byType(TextField),
      );

      await pressCtrlV(tester, field: field);
      await tester.enterText(field, 'Report');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(core.sentFiles, [document.path]);
      expect(core.sentFileCaptions, ['Report']);
      expect(core.sentImagePaths, isEmpty);
    });
  });
}
