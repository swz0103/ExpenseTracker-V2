@Tags(['timing'])
library;

import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/held.dart';
import '../support/trade_book.dart';

/// An import checks each sale it reads against its own stock's trades
/// (review 32 1.6). Before, each sale replayed every trade of the book
/// and those read before it (`holdsWith`, 5–8 ms at 100,000 entries): an
/// import of 3,000 sales into such a book ran for about 20 s on the host.
///
/// On a book of 100,000 entries, 3,000 of them trades of twenty stocks
/// ([tradeBook]), [_sales] sales and buys read oldest first are checked one after another
/// as the import does, and gated as a share of the old way, the whole
/// replay per sale, the least of [gateTries] runs; both must keep the same
/// sales. With `BENCH=1` the times are printed.
void main() {
  final bench = Platform.environment['BENCH'] != null;
  final today = tradeBookToday;

  test('an import\'s sales are checked against their own stock', () async {
    final ledger = tradeBook();
    expect(ledger.entries.length, 100000);
    final r = Random(11);
    // What an import read, oldest first: sales of up to 30,000 shares
    // (some more than are held), a buy now and then.
    final read = [
      for (var i = 0; i < _sales; i++)
        Entry(
          id: 'i$i',
          date: today.subtract(Duration(days: _sales - i)),
          type: i % 5 == 0 ? EntryType.buy : EntryType.sell,
          amount: 1000,
          account: 'bank',
          holding: '${1101 + r.nextInt(20)}',
          shares: 1 + r.nextInt(30000),
        ),
    ];
    final validator = ledger.entryValidator;

    List<String> before() {
      final added = <Entry>[];
      for (final e in read) {
        if (e.type == EntryType.sell &&
            !wholeBookHolds(ledger, [...added, e])) {
          continue;
        }
        added.add(e);
      }
      return [for (final e in added) e.id];
    }

    List<String> now() {
      final run = validator.tradeRun();
      final added = <String>[];
      for (final e in read) {
        if (e.type == EntryType.sell && !run.holds(e)) continue;
        run.add(e);
        added.add(e.id);
      }
      return added;
    }

    final kept = now();
    expect(kept, before());
    expect(kept.length, inExclusiveRange(_sales ~/ 5, _sales));

    Future<int> timed(void Function() run) => leastOf(gateTries, () async {
      final watch = Stopwatch()..start();
      run();
      return watch.elapsedMicroseconds;
    });
    final old = await timed(before);
    final checked = await timed(now);
    if (bench) {
      // ignore: avoid_print
      print('$_sales read: old $old µs; now $checked µs');
    }
    expect(
      checked / old,
      lessThanOrEqualTo(_most),
      reason:
          'checking $_sales trades took $checked µs, the whole replay per '
          'sale $old µs',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// How many trades the import reads.
const _sales = 200;

/// The largest share of the old way the check may take: about twice the
/// largest measured (thresholds.md).
const _most = 0.13;
