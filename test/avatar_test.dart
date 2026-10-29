import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tanglex_chat/src/data/chat_providers.dart';
import 'package:tanglex_chat/src/data/profile_image.dart';
import 'package:tanglex_chat/src/design/app_theme.dart';
import 'package:tanglex_chat/src/design/app_theme_controller.dart';
import 'package:tanglex_chat/src/shell/messenger_shell.dart';
import 'package:tanglex_chat/src/shell/widgets/peer_avatar.dart';

import 'support/fake_chat_core.dart';

final _now = DateTime(2026, 10, 26, 15, 0);

/// Noise defeats JPEG compression, so the encoder has to shrink the image to
/// meet the core's size cap instead of fitting on the first try.
Uint8List _noisyJpeg(int width, int height) {
  final random = Random(7);
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel
      ..r = random.nextInt(256)
      ..g = random.nextInt(256)
      ..b = random.nextInt(256);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

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

Future<FakeChatCore> _pumpShell(
  WidgetTester tester, {
  List<Map<String, dynamic>>? users,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final core = FakeChatCore(
    chats: demoChats(_now),
    messages: demoConversations(_now),
    now: _now,
    users: users,
  );
  await tester.pumpWidget(_app(core));
  await tester.pumpAndSettle();
  return core;
}

Map<String, dynamic> _userWithPhoto(String dataUri) => {
  'userId': 1,
  'localDisplayName': 'alex',
  'profile': {
    'displayName': 'Alex Morgan',
    'fullName': 'Alex Morgan Jr.',
    'shortDescr': 'Building TangleX',
    'image': dataUri,
  },
  'activeUser': true,
};

Future<void> _openProfile(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.chevron_right));
  await tester.pumpAndSettle();
}

void main() {
  test('profile photo is a square data URL within the core cap', () {
    final uri = profileImageDataUri(_noisyJpeg(1200, 800));
    expect(uri, isNotNull);
    expect(uri, startsWith('data:image/jpeg;base64,'));
    expect(uri!.length, lessThanOrEqualTo(maxProfileImageDataSize));

    final bytes = base64Decode(uri.substring(uri.indexOf('base64,') + 7));
    final decoded = img.decodeImage(bytes)!;
    expect(decoded.width, decoded.height);
  });

  // Negative control for the cap: the untouched noise JPEG is far above the
  // limit, so the value above is only under it because the loop shrinks.
  test('the raw noise image would not fit the cap', () {
    final raw = _noisyJpeg(1200, 800);
    final rawUriLength = 'data:image/jpeg;base64,'.length + base64Encode(raw).length;
    expect(rawUriLength, greaterThan(maxProfileImageDataSize));
  });

  test('non-image bytes are rejected', () {
    expect(profileImageDataUri(Uint8List.fromList([1, 2, 3, 4])), isNull);
    expect(profileImageBytes('not a data url'), isNull);
  });

  testWidgets('the avatar menu offers set and delete, delete clears the photo', (
    tester,
  ) async {
    final photo = profileImageDataUri(_noisyJpeg(64, 64))!;
    final core = await _pumpShell(tester, users: [_userWithPhoto(photo)]);
    await _openProfile(tester);

    await tester.tap(find.byKey(const ValueKey('profile-avatar')));
    await tester.pumpAndSettle();
    expect(find.text('Set new photo'), findsOneWidget);
    expect(find.text('Delete photo'), findsOneWidget);

    await tester.tap(find.text('Delete photo'));
    await tester.pumpAndSettle();

    final profile = core.users.first['profile'] as Map<String, dynamic>;
    expect(profile.containsKey('image'), isFalse);
    final avatar = tester.widget<PeerAvatar>(
      find.descendant(
        of: find.byKey(const ValueKey('profile-avatar')),
        matching: find.byType(PeerAvatar),
      ),
    );
    expect(avatar.imageBytes, isNull);
  });

  testWidgets('editing the name keeps the profile photo', (tester) async {
    final photo = profileImageDataUri(_noisyJpeg(64, 64))!;
    final core = await _pumpShell(tester, users: [_userWithPhoto(photo)]);
    await _openProfile(tester);

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)).first,
      'Alex Morganov',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final profile = core.users.first['profile'] as Map<String, dynamic>;
    expect(profile['displayName'], 'Alex Morganov');
    expect(profile['image'], photo);
  });
}
