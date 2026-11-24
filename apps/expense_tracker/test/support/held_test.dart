import 'package:flutter_test/flutter_test.dart';

import 'held.dart';

void main() {
  test('timeHeld gives the result and the longest hold', () async {
    final quiet = await timeHeld(() async => 7);
    expect(quiet.result, 7);

    final busy = await timeHeld(() async {
      final spin = Stopwatch()..start();
      while (spin.elapsedMilliseconds < 60) {}
      return 'done';
    });
    expect(busy.result, 'done');
    expect(busy.heldUs, greaterThanOrEqualTo(60000));
  });
}
