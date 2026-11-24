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

/// The journal's check runs on the screen's isolate, in slices (r13 F8):
/// at 100,000 entries the longest it holds the isolate, as a share of
/// the whole check run at once, stays under `parity_held_share`
/// (journal_thresholds.json), so it holds on any machine; and the hold
/// itself under `parity_held_ms`, so a slice that grows with the book is
/// caught though its share does not (review 18).
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
    Future<int> run({required bool sliced}) async {
      final ledger = book();
      final posted = await post(ledger);
      return (await timeHeld(() async {
        final watch = Stopwatch()..start();
        await checkParity(
          today: figuresOf(ledger),
          reader: posted.reader,
          pause: sliced
              ? () async {
                  if (watch.elapsed < journalSlice) return;
                  await Future<void>.delayed(Duration.zero);
                  watch.reset();
                }
              : null,
        );
      })).heldUs;
    }

    final whole = await leastOf(gateTries, () => run(sliced: false));
    final sliced = await leastOf(gateTries, () => run(sliced: true));
    final share = sliced / whole;
    // ignore: avoid_print
    print(
      'parity_held: at once ${whole ~/ 1000} ms; sliced ${sliced ~/ 1000} '
      'ms; share ${share.toStringAsFixed(3)}',
    );
    expect(share, lessThanOrEqualTo(limit));
    expect(sliced ~/ 1000, lessThanOrEqualTo(heldMs));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
