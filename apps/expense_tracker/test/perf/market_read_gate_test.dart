@Tags(['timing'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:expense_tracker/src/core/ledger/persistence/market_rows.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/market_days.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart' show StoredRow;

import '../support/held.dart';

/// A market read of a book kept five years (review 39 1): its day rows
/// read once, the months long gone folded into a row each, gated as a
/// share of the read before, which read every day row twice (each row
/// checked alone, then all of them). Day rows as a busy book has them:
/// 19 currencies' buying and selling rates and 15 closes on every
/// weekday. With `BENCH=1` the times are printed.
void main() {
  final bench = Platform.environment['BENCH'] != null;
  final today = BusinessDate(2026, 11, 25);

  test('a five-year market reads its day rows once, the old months '
      'folded', () async {
    final rows = <StoredRow>[
      StoredRow(0, marketShelf, 'quotes', '{"prices":{"2330":1000}}'),
    ];
    for (var i = 0; i < 5 * 365; i++) {
      final day = today.addDays(-i);
      if (day.isWeekend) continue;
      rows.add(
        StoredRow(
          0,
          marketShelf,
          marketDayId(day),
          jsonEncode({
            'rates': {for (var c = 0; c < 19; c++) 'C$c': 30 + c + i / 1000},
            'sell': {for (var c = 0; c < 19; c++) 'C$c': 31 + c + i / 1000},
            'closes': {for (var s = 0; s < 15; s++) '${1000 + s}': 100 + i},
          }),
        ),
      );
    }
    final folded = foldedMarket(rows, today);
    // About 286 weekdays of the last 400 days and a row for each of the
    // 50-odd months before, rather than 1,300 days.
    expect(folded.rows.length, lessThan(400));

    Future<int> timed(void Function() run) => leastOf(gateTries, () async {
      final watch = Stopwatch()..start();
      run();
      return watch.elapsedMicroseconds;
    });
    final before = await timed(() {
      // As it was: every row read alone to be checked, then all again.
      final readable = [
        for (final row in rows)
          if (_reads(row)) row,
      ];
      marketFrom(readable);
    });
    final now = await timed(() => readMarket(folded.rows));
    if (bench) {
      // ignore: avoid_print
      print('before $before µs; now $now µs');
    }
    expect(
      now / before,
      lessThanOrEqualTo(_most),
      reason: 'the read took $now µs, the old one $before µs',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}

bool _reads(StoredRow row) {
  try {
    marketFrom([row]);
    return true;
  } on FormatException catch (error) {
    fail('$error');
  }
}

/// The largest share of the old read the read may take: about twice the
/// largest measured (thresholds.md).
const _most = 0.22;
