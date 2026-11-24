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

  test('leastOf runs every try and keeps the least', () async {
    final runs = [5, 2, 9];
    var i = 0;
    expect(await leastOf(3, () async => runs[i++]), 2);
    expect(i, 3);
    expect(gateTries, greaterThan(1));
  });
}
