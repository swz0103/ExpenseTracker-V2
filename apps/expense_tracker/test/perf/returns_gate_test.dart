@Tags(['timing'])
library;

import 'dart:io';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/investments/ui/investments.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/held.dart';
import '../support/whole_book_returns.dart';

/// The 投資 pages read the yearly return and the dividend guesses kept
/// per change of the entries and the market (review 32 1.1). Before,
/// every build worked them out from the whole book, 隱藏金額 included,
/// and a holding's next dividend guessed every holding to keep one.
///
/// On the demo book with 100,000 entries more (twelve holdings, their
/// trades and dividends), what the pages read after a save (worked out
/// again), after 隱藏金額 (kept) and a holding's next dividend alone after
/// a save are gated as shares of the old whole-book working, each the
/// least of [gateTries] runs, so they hold on any machine. With `BENCH=1`
/// the times are printed.
void main() {
  final bench = Platform.environment['BENCH'] != null;

  test('the returns are worked out once per change, a stock from its own '
      'trades', () async {
    final ledger = demoLedger();
    final today = ledger.today;
    final accounts = [
      for (final a in ledger.accounts.all)
        if (!a.kind.isDebt) a.id,
    ];
    final spending = [
      for (final c in ledger.categories.forEntries(income: false)) c.name,
    ];
    ledger.entryCommands.addAll([
      for (var i = 0; i < 100000; i++)
        Entry(
          id: 'b$i',
          date: today.subtract(Duration(days: i * 1095 ~/ 100000)),
          type: EntryType.expense,
          amount: 40 + i * 37 % 900,
          account: accounts[i % accounts.length],
          category: spending[i % spending.length],
        ),
    ]);
    final code = ledger.holdings.all.first.code;
    expect(WholeBookReturns(ledger).expectedDividends(), isNotEmpty);
    var saved = 0;
    void save() => ledger.entryCommands.add(
      Entry(
        id: 'n${saved++}',
        date: today,
        type: EntryType.expense,
        amount: 50,
        account: accounts.first,
        category: spending.first,
      ),
    );
    // What the hero, the 股息 tab and a holding's page read.
    void pages(
      double? Function({String? code}) rate,
      List<Object?> Function() expected,
      Object? Function(String) next,
      List<int> Function(String) months,
    ) {
      rate();
      expected();
      rate(code: code);
      next(code);
      months(code);
    }

    Future<int> timed(void Function() run) => leastOf(gateTries, () async {
      final watch = Stopwatch()..start();
      run();
      return watch.elapsedMicroseconds;
    });

    final old = await timed(() {
      final before = WholeBookReturns(ledger);
      pages(
        before.rate,
        before.expectedDividends,
        before.nextDividend,
        before.payingMonths,
      );
    });
    final oldNext = await timed(
      () => WholeBookReturns(ledger).nextDividend(code),
    );
    // Warmed up: the stock index and the month lists are built.
    save();
    returnsOf(ledger).expectedDividends();

    final changed = await leastOf(gateTries, () async {
      save();
      final watch = Stopwatch()..start();
      final returns = returnsOf(ledger);
      pages(
        returns.rate,
        returns.expectedDividends,
        returns.nextDividend,
        returns.payingMonths,
      );
      return watch.elapsedMicroseconds;
    });
    final kept = await leastOf(gateTries, () async {
      ledger.amounts.toggle();
      final watch = Stopwatch()..start();
      final returns = returnsOf(ledger);
      pages(
        returns.rate,
        returns.expectedDividends,
        returns.nextDividend,
        returns.payingMonths,
      );
      return watch.elapsedMicroseconds;
    });
    final next = await leastOf(gateTries, () async {
      save();
      final watch = Stopwatch()..start();
      returnsOf(ledger).nextDividend(code);
      return watch.elapsedMicroseconds;
    });
    expect(
      returnsOf(ledger).expectedDividends(),
      WholeBookReturns(ledger).expectedDividends(),
    );
    if (bench) {
      // ignore: avoid_print
      print(
        'old $old µs; after a save $changed µs; kept $kept µs; '
        'old next $oldNext µs; next after a save $next µs',
      );
    }
    expect(
      changed / old,
      lessThanOrEqualTo(_changedMost),
      reason:
          'after a save the pages\' reads took $changed µs, the old whole '
          'book $old µs',
    );
    expect(
      kept / old,
      lessThanOrEqualTo(_keptMost),
      reason:
          'after 隱藏金額 the pages\' reads took $kept µs, the old whole book '
          '$old µs: the returns were worked out again',
    );
    expect(
      next / oldNext,
      lessThanOrEqualTo(_nextMost),
      reason:
          'a holding\'s next dividend took $next µs, the old way $oldNext '
          'µs: every holding was guessed',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// The largest share of the old whole-book working the pages' reads may
/// take after a save: about twice the largest measured (thresholds.md).
const _changedMost = 0.2;

/// The largest share they may take with nothing but 隱藏金額 changed.
const _keptMost = 0.0006;

/// The largest share of the old next dividend a holding's may take after
/// a save.
const _nextMost = 0.003;
