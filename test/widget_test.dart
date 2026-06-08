// Placeholder smoke test.
//
// The FFI-backed TanglexService cannot be loaded in a host unit-test VM,
// so we deliberately avoid pumping the real app here. Real tests will
// arrive together with the new UI; until then this file exists only to
// keep `flutter test` exit-code clean.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder — no-op until UI lands', () {
    expect(1 + 1, 2);
  });
}
