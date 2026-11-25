@Tags(['timing'])
library;

import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/entries/model/compose_form.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/held.dart';

/// The sale form's 已實現損益 costs the sold stock's trades, once per
/// change of what it rests on (review 19 4.1). Before, every keystroke in
/// the form copied every entry before the sale and replayed all of them,
/// every stock's, to read one: a whole-book cost on each rebuild.
///
/// On a book of 100,000 entries, 3,000 of them trades of twenty stocks,
/// a change of the shares (worked out again, from the stock's trades) and
/// a read with nothing changed (kept) are gated as shares of the old
/// whole-book replay, each the least of [gateTries] runs, so they hold on
/// any machine. With `BENCH=1` the times are printed.
void main() {
  final today = DateTime.utc(2026, 10, 4);
  final bench = Platform.environment['BENCH'] != null;

  Ledger book() {
    final r = Random(7);
    final entries = <Entry>[];
    // Twenty stocks over three years: a buy of 1,000 shares every 10
    // days and a sale of 500 every 20, so a sale never takes more than
    // is held.
    for (var s = 0; s < 20; s++) {
      final code = '${1101 + s}';
      for (var k = 0; k < 100; k++) {
        final date = today.subtract(Duration(days: 1000 - k * 10 - s % 7));
        entries.add(
          Entry(
            id: 'b$s-$k',
            date: date,
            type: EntryType.buy,
            amount: 50000 + r.nextInt(20000),
            account: 'bank',
            holding: code,
            shares: 1000,
            fee: 20,
          ),
        );
        if (k.isOdd) {
          entries.add(
            Entry(
              id: 's$s-$k',
              date: date.add(const Duration(days: 1)),
              type: EntryType.sell,
              amount: 30000 + r.nextInt(20000),
              account: 'bank',
              holding: code,
              shares: 500,
              fee: 20,
              tax: 90,
            ),
          );
        }
      }
    }
    final trades = entries.length;
    for (var i = 0; i < 100000 - trades; i++) {
      entries.add(
        Entry(
          id: 'e$i',
          date: today.subtract(Duration(days: r.nextInt(1000))),
          type: EntryType.expense,
          amount: 30 + r.nextInt(2000),
          account: 'bank',
          category: '飲食',
        ),
      );
    }
    return Ledger(
      today: today,
      accounts: const [Account('bank', '銀行', AccountKind.bank, 0)],
      categories: const [],
      entries: entries,
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
  }

  test('a sale\'s cost replays its stock alone, once per change', () async {
    final ledger = book();
    expect(ledger.entries.length, 100000);
    final sale = ledger.entries.byId('s10-99')!;
    final form = ComposeForm(ledger, type: EntryType.sell, editing: sale);

    // The old way: every entry before the sale, replayed whole.
    final before = [
      for (final e in countedOn(ledger.entries.all, ledger.today))
        if (e.id != sale.id && !e.date.isAfter(sale.date)) e,
    ];
    final whole = await leastOf(gateTries, () async {
      final watch = Stopwatch()..start();
      ledger.holdings.saleCostWith(before, sale.holding!, 500);
      return watch.elapsedMicroseconds;
    });

    var shares = 400;
    final changed = await leastOf(gateTries, () async {
      form.setShares(shares += 10);
      final watch = Stopwatch()..start();
      form.saleCost;
      return watch.elapsedMicroseconds;
    });
    expect(form.saleCost, isNotNull);
    final kept = await leastOf(gateTries, () async {
      final watch = Stopwatch()..start();
      form.saleCost;
      return watch.elapsedMicroseconds;
    });
    if (bench) {
      // ignore: avoid_print
      print('whole $whole µs; changed $changed µs; kept $kept µs');
    }
    expect(
      changed / whole,
      lessThanOrEqualTo(_changedMost),
      reason:
          'a change of the shares took $changed µs, the whole book '
          '$whole µs: every stock was replayed',
    );
    expect(
      kept / whole,
      lessThanOrEqualTo(_keptMost),
      reason:
          'a read with nothing changed took $kept µs, the whole book '
          '$whole µs: the cost was not kept',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// The largest share of the whole-book replay a change of the shares may
/// take: about twice the largest measured (thresholds.md).
const _changedMost = 0.2;

/// The largest share a read with nothing changed may take: about twice
/// the largest measured, no less than the timer's 1 µs over a 2 ms
/// replay (thresholds.md).
const _keptMost = 0.0005;
