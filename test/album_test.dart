import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/conversation_panel.dart';
import 'package:tanglex_chat/src/shell/media_group_layout.dart';
import 'package:tanglex_chat/src/shell/models.dart';

final _now = DateTime(2026, 10, 29, 12, 0);

String _photoDataUri({int width = 400, int height = 300, int tone = 120}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(tone, 120, 90));
  return 'data:image/jpeg;base64,${base64Encode(img.encodeJpg(image))}';
}

Map<String, dynamic> _photoJson({
  required int itemId,
  required DateTime ts,
  bool fromMe = true,
  String text = '',
  int width = 400,
  int height = 300,
  List<Map<String, dynamic>> reactions = const [],
  String fileName = 'photo.jpg',
}) {
  return {
    'chatDir': {'type': fromMe ? 'directSnd' : 'directRcv'},
    'meta': {
      'itemId': itemId,
      'itemTs': ts.toUtc().toIso8601String(),
      'itemText': text,
      'itemStatus': {'type': fromMe ? 'sndSent' : 'rcvNew'},
    },
    'content': {
      'type': fromMe ? 'sndMsgContent' : 'rcvMsgContent',
      'msgContent': {
        'type': 'image',
        'text': text,
        'image': _photoDataUri(width: width, height: height),
      },
    },
    'file': {
      'fileId': itemId,
      'fileName': fileName,
      'fileSize': 123456,
      'fileStatus': {'type': 'sndComplete'},
      'fileSource': <String, dynamic>{},
    },
    'reactions': reactions,
  };
}

Map<String, dynamic> _reaction(String emoji, {bool mine = false}) => {
  'reaction': {'emoji': emoji},
  'totalReacted': 1,
  'userReacted': mine,
};

List<MessageItem> _chat(List<Map<String, dynamic>> raw) =>
    buildTimeline(raw, now: _now);

void main() {
  group('album merging', () {
    test('consecutive photos sent together become one mosaic', () {
      final base = DateTime.utc(2026, 10, 29, 9, 0, 0);
      final timeline = _chat([
        _photoJson(itemId: 1, ts: base, text: 'first'),
        _photoJson(
          itemId: 2,
          ts: base.add(const Duration(milliseconds: 300)),
        ),
        _photoJson(
          itemId: 3,
          ts: base.add(const Duration(milliseconds: 900)),
        ),
      ]);
      final bubbles = timeline.where((m) => !m.isDateSeparator).toList();
      expect(bubbles, hasLength(1));
      final album = bubbles.single;
      expect(album.album, hasLength(3));
      expect(album.text, 'first');
      // The bubble keeps the freshest item, so replies and reactions land on
      // the item whose time is displayed.
      expect(album.itemId, 3);
      expect(album.time, bubbles.single.time);
      expect(album.album.map((tile) => tile.itemId), [1, 2, 3]);
      expect(album.album.every((tile) => tile.bytes != null), isTrue);
    });

    test('captions of the merged items stack in order', () {
      final base = DateTime.utc(2026, 10, 29, 9, 0, 0);
      final timeline = _chat([
        _photoJson(itemId: 1, ts: base, text: 'a'),
        _photoJson(
          itemId: 2,
          ts: base.add(const Duration(seconds: 1)),
          text: 'b',
        ),
      ]);
      expect(timeline.where((m) => !m.isDateSeparator).single.text, 'a\nb');
    });

    test('photos sent apart stay separate', () {
      final base = DateTime.utc(2026, 10, 29, 9, 0, 0);
      final timeline = _chat([
        _photoJson(itemId: 1, ts: base),
        _photoJson(itemId: 2, ts: base.add(const Duration(seconds: 4))),
      ]);
      final bubbles = timeline.where((m) => !m.isDateSeparator).toList();
      expect(bubbles, hasLength(2));
      expect(bubbles.every((m) => m.album.isEmpty), isTrue);
    });

    test('opposite directions never join', () {
      final base = DateTime.utc(2026, 10, 29, 9, 0, 0);
      final timeline = _chat([
        _photoJson(itemId: 1, ts: base),
        _photoJson(
          itemId: 2,
          ts: base.add(const Duration(milliseconds: 200)),
          fromMe: false,
        ),
      ]);
      expect(timeline.where((m) => !m.isDateSeparator), hasLength(2));
    });

    test('an album stops at ten tiles like GroupedMedia::kMaxSize', () {
      final base = DateTime.utc(2026, 10, 29, 9, 0, 0);
      final timeline = _chat([
        for (var i = 0; i < 11; i++)
          _photoJson(
            itemId: i + 1,
            ts: base.add(Duration(milliseconds: 100 * i)),
          ),
      ]);
      final bubbles = timeline.where((m) => !m.isDateSeparator).toList();
      expect(bubbles, hasLength(2));
      expect(bubbles.first.album, hasLength(groupedMediaMaxCount));
      expect(bubbles.last.album, isEmpty);
    });

    test('stickers are not album tiles', () {
      final base = DateTime.utc(2026, 10, 29, 9, 0, 0);
      final timeline = _chat([
        _photoJson(itemId: 1, ts: base),
        _photoJson(
          itemId: 2,
          ts: base.add(const Duration(milliseconds: 100)),
          fileName: 'st__12345.webp',
        ),
      ]);
      final bubbles = timeline.where((m) => !m.isDateSeparator).toList();
      expect(bubbles, hasLength(2));
      expect(bubbles.every((m) => m.album.isEmpty), isTrue);
    });

    test('reactions of every tile are summed on the bubble', () {
      final base = DateTime.utc(2026, 10, 29, 9, 0, 0);
      final timeline = _chat([
        _photoJson(itemId: 1, ts: base, reactions: [_reaction('👍')]),
        _photoJson(
          itemId: 2,
          ts: base.add(const Duration(milliseconds: 200)),
          reactions: [_reaction('👍', mine: true), _reaction('❤')],
        ),
      ]);
      final album = timeline.where((m) => !m.isDateSeparator).single;
      expect(album.reactions, hasLength(2));
      expect(album.reactions.first.emoji, '👍');
      expect(album.reactions.first.count, 2);
      expect(album.reactions.first.mine, isTrue);
    });
  });

  group('Telegram grouped layout', () {
    test('two wide photos stack vertically', () {
      final layout = layoutMediaGroup([1.6, 1.6]);
      expect(layout, hasLength(2));
      expect(layout[0].width, groupedMediaWidthMax);
      expect(layout[0].height, 213);
      expect(layout[1].top, 217);
      expect(layout[1].height, 213);
    });

    test('two squares sit side by side', () {
      final layout = layoutMediaGroup([1, 1]);
      expect(layout[0].width, 213);
      expect(layout[1].left, 217);
      expect(layout[0].height, 213);
    });

    test('a portrait first tile takes the left column', () {
      final layout = layoutMediaGroup([0.7, 1, 1]);
      expect(layout[0].height, groupedMediaWidthMax);
      expect(layout[1].left, layout[0].right + groupedMediaSkip);
      expect(layout[1].top, 0);
      expect(layout[2].top, layout[1].bottom + groupedMediaSkip);
      expect(layout[2].bottom, layout[0].bottom);
    });

    test('four wide photos get a full-width hero on top', () {
      final layout = layoutMediaGroup([1.5, 1.5, 1.5, 1.5]);
      expect(layout, hasLength(4));
      expect(layout[0].width, groupedMediaWidthMax);
      expect(layout[0].height, 281);
      expect(layout[1].top, 285);
      expect(layout[3].right, groupedMediaWidthMax);
    });

    test('five photos fall back to the complex two-row split', () {
      final layout = layoutMediaGroup([1, 1, 1, 1, 1]);
      expect(layout, hasLength(5));
      expect(layout[0].height, 213);
      expect(layout[2].top, 217);
      expect(layout[4].right, groupedMediaWidthMax);
      expect(layout[2].height, 141);
    });

    test('a panorama forces the complex layouter', () {
      final layout = layoutMediaGroup([2.5, 1]);
      expect(layout[0].width, groupedMediaWidthMax);
      expect(layout[1].top, layout[0].height + groupedMediaSkip);
      expect(layout[0].height, lessThan(layout[1].top));
    });

    test('every layout keeps tiles inside the group and apart', () {
      for (final ratios in [
        <double>[1, 1],
        <double>[1.6, 1.6],
        <double>[0.7, 1, 1],
        <double>[1.5, 1.5, 1.5, 1.5],
        <double>[1, 1, 1, 1, 1],
        <double>[2.5, 1],
        <double>[1, 1, 1, 1, 1, 1, 1],
        <double>[0.7, 1.4, 1.9, 0.8, 1, 1.1, 1.2, 1.3, 1.1, 0.9],
      ]) {
        final layout = layoutMediaGroup(ratios);
        expect(layout, hasLength(ratios.length));
        _expectTilesFit(layout, groupedMediaWidthMax);
      }
    });

    test('narrow bubbles scale the whole grid with its spacing', () {
      final scaled = scaleGroupLayout(layoutMediaGroup([1, 1]), 281);
      expect(scaled[1].right, 281);
      expect(scaled[0].width, 139);
      expect(scaled[1].left, scaled[0].right + 3);
      expect(scaled[0].height, 139);
    });
  });

  group('album bubble', () {
    Future<void> pumpAlbum(
      WidgetTester tester,
      MessageItem message, {
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
                  preview: 'photo',
                  time: '12:00',
                ),
                messages: [message],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    MessageItem album(int count) {
      final bytes = base64Decode(
        _photoDataUri().substring('data:image/jpeg;base64,'.length),
      );
      return MessageItem(
        text: '',
        time: '12:00',
        timestamp: _now,
        outgoing: true,
        mediaLabel: 'Photo',
        imageBytes: bytes,
        itemId: 10,
        album: [
          for (var i = 0; i < count; i++)
            AlbumTile(bytes: bytes, itemId: i + 1),
        ],
      );
    }

    testWidgets('renders one tile per album item', (tester) async {
      await pumpAlbum(tester, album(3));
      expect(find.byKey(const ValueKey('album-tile-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('album-tile-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('album-tile-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('album-tile-3')), findsNothing);
      final mosaic = tester.getSize(
        find.byKey(const ValueKey('album-tile-0')),
      );
      expect(mosaic.width, greaterThan(0));
    });

    testWidgets('tapping a tile opens the viewer on that tile', (
      tester,
    ) async {
      await pumpAlbum(tester, album(3));
      await tester.tap(find.byKey(const ValueKey('album-tile-1')));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsNothing);
    });

    testWidgets('a single photo also opens the viewer', (tester) async {
      final bytes = base64Decode(
        _photoDataUri().substring('data:image/jpeg;base64,'.length),
      );
      await pumpAlbum(
        tester,
        MessageItem(
          text: '',
          time: '12:00',
          timestamp: _now,
          outgoing: true,
          mediaLabel: 'Photo',
          imageBytes: bytes,
          itemId: 4,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('media-preview')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('1 / 1'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsNothing);
    });
  });
}

/// Guards the geometry invariants the mosaic relies on: every tile is inside
/// the group and rows never overlap.
void _expectTilesFit(List<GroupedMediaLayout> layout, int width) {
  for (final tile in layout) {
    expect(tile.left, greaterThanOrEqualTo(0));
    expect(tile.top, greaterThanOrEqualTo(0));
    expect(tile.right, lessThanOrEqualTo(width));
  }
  for (var i = 0; i < layout.length; i++) {
    for (var j = i + 1; j < layout.length; j++) {
      final a = layout[i];
      final b = layout[j];
      final overlapX = math.min(a.right, b.right) - math.max(a.left, b.left);
      final overlapY = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
      expect(overlapX <= 0 || overlapY <= 0, isTrue, reason: 'tiles $i/$j');
    }
  }
}
