import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/providers/persistent_store.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/messenger_shell.dart';

import 'support/fake_chat_core.dart';

final _now = DateTime(2026, 10, 26, 15, 0);

ChatPreview _direct(String ref, String name) => ChatPreview(
  chatRef: ref,
  chatType: 'contact',
  displayName: name,
  contactStatus: 'active',
  connStatusType: 'ready',
);

Widget _app(FakeChatCore core) {
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
      child: MaterialApp(theme: theme.toMaterial(), home: const MessengerShell()),
    ),
  );
}

ProviderContainer _containerFor(FakeChatCore core) {
  final container = ProviderContainer(
    overrides: [
      chatCoreProvider.overrideWithValue(core),
      clockProvider.overrideWithValue(() => _now),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Map<String, dynamic> _photo({
  required int progress,
  required int total,
  String status = 'sndTransfer',
}) => imageItem(
  time: _now,
  fileName: 'photo.jpg',
  size: 400000,
  fromMe: true,
  fileId: 11,
  fileStatus: status,
  progress: progress,
  total: total,
);

void main() {
  test('the core file status becomes a clamp-able upload fraction', () {
    final timeline = buildTimeline([_photo(progress: 1000, total: 4000)]);
    final bubble = timeline.last;
    expect(bubble.transferStatus, 'sndTransfer');
    expect(bubble.isTransferring, isTrue);
    expect(bubble.transferFraction, closeTo(0.25, 1e-9));

    final done = buildTimeline([_photo(progress: 4000, total: 4000, status: 'sndSent')]);
    expect(done.last.isTransferring, isFalse);
    expect(done.last.transferFraction, isNull);
  });

  test('upload progress events refresh the timeline', () async {
    final core = FakeChatCore(
      chats: [_direct('@1', 'Alice')],
      messages: {
        '@1': [_photo(progress: 100, total: 400)],
      },
      now: _now,
    );
    final container = _containerFor(core);
    var timeline = await container.read(messagesProvider('@1').future);
    expect(timeline.last.transferFraction, closeTo(0.25, 1e-9));

    // `sndFileProgressXFTP` is what the core emits while XFTP uploads; the
    // item in the DB carries the new byte counters.
    core.messages['@1'] = [_photo(progress: 300, total: 400)];
    core.emitEvent('sndFileProgressXFTP');
    await Future<void>.delayed(const Duration(milliseconds: 400));

    timeline = container.read(messagesProvider('@1')).valueOrNull!;
    expect(timeline.last.transferFraction, closeTo(0.75, 1e-9));
  });

  test('small incoming photos are accepted automatically, big ones are not', () async {
    final core = FakeChatCore(
      chats: [_direct('@1', 'Alice')],
      messages: {
        '@1': [
          imageItem(
            time: _now,
            fileName: 'small.jpg',
            size: 300000,
            fileId: 21,
            fileStatus: 'rcvInvitation',
          ),
          imageItem(
            time: _now.add(const Duration(seconds: 1)),
            fileName: 'huge.jpg',
            size: 900000,
            fileId: 22,
            fileStatus: 'rcvInvitation',
          ),
        ],
      },
      now: _now,
    );
    final container = _containerFor(core);
    await container.read(messagesProvider('@1').future);
    expect(core.receivedFileIds, [21]);
  });

  testWidgets('tapping a pending document downloads it through the core', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final core = FakeChatCore(
      chats: [_direct('@1', 'Alice')],
      messages: {
        '@1': [
          documentItem(
            time: _now,
            fileName: 'quarterly-report.pdf',
            size: 2489344,
            fileId: 33,
            fileStatus: 'rcvInvitation',
          ),
        ],
      },
      now: _now,
    );
    await tester.pumpWidget(_app(core));
    await tester.pumpAndSettle();
    expect(core.receivedFileIds, isEmpty);

    await tester.tap(find.byKey(const ValueKey('document-card')));
    await tester.pumpAndSettle();
    expect(core.receivedFileIds, [33]);
  });

  testWidgets('the bubble paints the full file and the upload ring', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Sync I/O only: `testWidgets` runs under a fake clock, so a real
    // `await createTemp()` would never complete.
    final dir = Directory.systemTemp.createTempSync('tanglex-media');
    addTearDown(() => dir.deleteSync(recursive: true));
    final photo = File('${dir.path}/full.png');
    final preview = demoImageUri().split(',').last;
    photo.writeAsBytesSync(base64Decode(preview));

    final core = FakeChatCore(
      chats: [_direct('@1', 'Alice')],
      messages: {
        '@1': [
          imageItem(
            time: _now,
            fileName: 'full.png',
            size: 400000,
            fromMe: true,
            fileId: 11,
            fileStatus: 'sndTransfer',
            progress: 100,
            total: 400,
            filePath: photo.path,
          ),
        ],
      },
      now: _now,
    );
    await tester.pumpWidget(_app(core));
    await tester.pumpAndSettle();

    final panel = find.byType(ConversationPanel);
    final images = tester
        .widgetList<Image>(
          find.descendant(of: panel, matching: find.byType(Image)),
        )
        .where((image) => image.image is FileImage)
        .map((image) => (image.image as FileImage).file.path);
    expect(images, contains(photo.path));

    final ring = find.descendant(
      of: panel,
      matching: find.byType(CircularProgressIndicator),
    );
    expect(ring, findsOneWidget);
    expect(tester.widget<CircularProgressIndicator>(ring).value, 0.25);

    // Upload completes: the core stops reporting sndTransfer and the ring goes.
    core.messages['@1'] = [
      imageItem(
        time: _now,
        fileName: 'full.png',
        size: 400000,
        fromMe: true,
        fileId: 11,
        fileStatus: 'sndSent',
        filePath: photo.path,
      ),
    ];
    core.emitEvent('sndFileCompleteXFTP');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: panel, matching: find.byType(CircularProgressIndicator)),
      findsNothing,
    );
  });
}
