// Minimal smoke test: design system primitives.
//
// We do not try to pump the full app because TanglexService starts an FFI
// runtime that cannot be loaded in a host unit-test environment.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/ui/design/design.dart';

void main() {
  testWidgets('AppAvatar renders initials for a given name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: AppAvatar(name: 'John Doe'),
        ),
      ),
    );

    expect(find.text('JD'), findsOneWidget);
  });

  test('Avatar palette is deterministic for the same seed', () {
    final a = AppColors.avatarColorFor('Alice');
    final b = AppColors.avatarColorFor('Alice');
    expect(a, equals(b));
  });

  test('Different seeds may map to different colors', () {
    final colors = <Color>{};
    for (final name in ['Alice', 'Bob', 'Charlie', 'Dave', 'Eve', 'Frank']) {
      colors.add(AppColors.avatarColorFor(name));
    }
    // Not strict because hash collisions are possible — but with 6 distinct
    // seeds we expect at least 2 different colors out of the palette of 8.
    expect(colors.length, greaterThan(1));
  });

  test('Spacing scale stays on the 4-point grid', () {
    expect(AppSpacing.s1, 4);
    expect(AppSpacing.s2, 8);
    expect(AppSpacing.s3, 12);
    expect(AppSpacing.s4, 16);
    expect(AppSpacing.s5, 20);
    expect(AppSpacing.s6, 24);
  });
}
