@Tags(['timing'])
library;

import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/held.dart';
import '../support/trade_book.dart';

/// An ordinary save of a sale asks whether the book still holds its
/// shares (`EntryValidator.holdsWith`). Before FIX-R34 that replayed the
/// whole book with the sale: 4–6 ms a sale at 100,000 entries. Now only
/// the sale's own stock is replayed, every other one answered once until
/// a trade of it changes.
///
/// On the book of [tradeBook], [_saves] sales of the twenty stocks are
/// saved one after another; each is asked first, and timed, both the new
/// way and the old ([wholeBookHolds]), which must answer alike. The new
/// way is gated as a share of the old, the least of [gateTries] runs.
/// With `BENCH=1` the times are printed.
void main() {
  final bench = Platform.environment['BENCH'] != null;
  final today = tradeBookToday;

  test('a sale saved is held to its own stock', () async {
    Future<(int, int)> run() async {
      final ledger = tradeBook();
      final validator = ledger.entryValidator;
      final r = Random(5);
      var old = 0;
      var now = 0;
      final watch = Stopwatch();
      for (var i = 0; i < _saves; i++) {
        // A sale of up to 300 shares today: each stock holds 75,000.
        final sale = Entry(
          id: 'sale$i',
          date: today,
          type: EntryType.sell,
          amount: 1000,
          account: 'bank',
          holding: '${1101 + r.nextInt(20)}',
          shares: 1 + r.nextInt(300),
        );
        watch
          ..reset()
          ..start();
        final whole = wholeBookHolds(ledger, [sale]);
        old += watch.elapsedMicroseconds;
        watch
          ..reset()
          ..start();
        final holds = validator.holdsWith([sale]);
        now += watch.elapsedMicroseconds;
        expect(holds, whole, reason: sale.id);
        expect(holds, isTrue, reason: sale.id);
        ledger.entryCommands.add(sale);
      }
      expect(ledger.entries.length, 100000 + _saves);
      return (old, now);
    }

    var old = 1 << 62;
    var now = 1 << 62;
    for (var i = 0; i < gateTries; i++) {
      final (o, n) = await run();
      old = min(old, o);
      now = min(now, n);
    }
    if (bench) {
      // ignore: avoid_print
      print('$_saves saves: old $old µs; now $now µs');
    }
    expect(
      now / old,
      lessThanOrEqualTo(_most),
      reason:
          'asking $_saves saves took $now µs, the whole replay per save '
          '$old µs',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// How many sales are saved.
const _saves = 40;

/// The largest share of the old way the check may take: about twice the
/// largest measured (thresholds.md).
const _most = 0.25;
