/// The journal's check runs on the screen's isolate, in slices (r13 F8):
/// at 100,000 entries the longest it holds the isolate, as a share of
/// the whole check run at once, stays under `parity_held_share`
/// (journal_thresholds.json), so it holds on any machine; and the hold
/// itself under `parity_held_ms`, so a slice that grows with the book is
/// caught though its share does not (review 18). Both judged on
/// interleaved pairs the host did not stall (held.dart, `shareOf`): the
/// hold in ms is a figure of this machine, which a busy host inflates
/// most (review 25). That the check offers its pauses at all is counted,
/// not timed, in parity_test.dart.
@Tags(['timing'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/core/ledger/journal/parity.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/journal_keeper.dart'
    show journalSlice;
import 'package:flutter_test/flutter_test.dart';

import '../baseline/baseline_ledger.dart';
import '../core/ledger/journal/posted_book.dart';
import '../support/held.dart';

void main() {
  final today = day(2026, 10, 4);

  /// 100,000 entries over five years on a bank, cash and a card.
  Ledger book() => ledgerOf(
    today: today,
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 1000000),
      Account('cash', '現金', AccountKind.cash, 5000),
      Account('card', '卡', AccountKind.card, 0, closingDay: 5, dueDay: 20),
    ],
    categories: [Category('飲食', 'food', 0xFF111111)],
    entries: [
      for (var i = 0; i < 100000; i++)
        entryOf(
          'e$i',
          today.subtract(Duration(days: i % 1800)),
          EntryType.expense,
          10 + i % 900,
          ['bank', 'cash', 'card'][i % 3],
          category: '飲食',
        ),
    ],
  );

  test('the check of a 100,000-entry book holds the screen for a small '
      'share of the check run at once', () async {
    final limits = jsonDecode(
      File('test/perf/journal_thresholds.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final limit = (limits['parity_held_share']! as num).toDouble();
    final heldMs = limits['parity_held_ms']! as int;
    var pausesTaken = 0;
    Future<Held<void>> run({required bool sliced}) async {
      // A fresh book each run: the first balance of an account is worked
      // out cold, as on opening.
      final ledger = book();
      final posted = await post(ledger);
      return timeHeld(() async {
        final watch = Stopwatch()..start();
        await checkParity(
          today: figuresOf(ledger),
          reader: posted.reader,
          pause: sliced
              ? () async {
                  if (watch.elapsed < journalSlice) return;
                  pausesTaken++;
                  await Future<void>.delayed(Duration.zero);
                  watch.reset();
                }
              : null,
        );
      });
    }

    // Warm up both, so neither is charged for compiling (the first sliced
    // run on CI held 113 ms, the next four 68–75).
    await run(sliced: true);
    await run(sliced: false);
    pausesTaken = 0;
    final result = await shareOf(
      apart: () => run(sliced: true),
      whole: () => run(sliced: false),
      limit: limit,
      apartMostUs: heldMs * 1000,
    );
    // ignore: avoid_print
    print(
      'parity_held: $pausesTaken pauses taken in ${result.pairs.length} '
      'sliced checks',
    );
    expect(pausesTaken, greaterThan(result.pairs.length));
    expectShare(result, 'parity_held');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
