// The property the journal keeps: any valid book, posted afresh, gives
// every figure the app shows (review 5's generator, 60 seeds; review 9's
// extended one, 120 seeds on two days, 預定 entries included).
import 'package:flutter_test/flutter_test.dart';

import '../../../baseline/baseline_ledger.dart';
import 'random_book.dart';

void main() {
  test('r5 generator, 60 seeds, replay parity', () async {
    final fails = <String>[];
    for (var s = 1; s <= 60; s++) {
      final b = generate(s, 200);
      final d = await diff(b.ledger);
      if (d != null) fails.add('seed $s:\n$d');
    }
    expect(fails, isEmpty, reason: fails.take(4).join('\n'));
  }, timeout: const Timeout(Duration(minutes: 10)));

  for (final today in [day(2026, 10, 31), day(2026, 9, 10)]) {
    test('extended generator, 120 seeds, today $today', () async {
      final fails = <String>[];
      var entries = 0;
      for (var s = 1; s <= 120; s++) {
        final (l, log) = gen(s, 150, today);
        entries += log.length;
        final d = await diff(l);
        if (d != null) fails.add('seed $s (${log.length} entries):\n$d');
      }
      // ignore: avoid_print
      print(
        'ext: $entries entries; ${fails.length} failing\n${fails.take(4).join('\n')}',
      );
      expect(fails, isEmpty, reason: fails.take(4).join('\n'));
    }, timeout: const Timeout(Duration(minutes: 15)));
  }
}
