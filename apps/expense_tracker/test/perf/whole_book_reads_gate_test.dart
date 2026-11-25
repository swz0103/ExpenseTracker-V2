@Tags(['timing'])
library;

import 'dart:io';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/held.dart';
import '../support/whole_book_reads.dart';

/// After a save the reads over the whole book count the saved month again
/// and add up the rest as kept (review 32 1.2). Before, one save made
/// eight of them cold, and 記一筆 opened after it paid for five (about
/// 24 ms on the host at 100,000 entries) before its first frame.
///
/// On the demo book with 100,000 entries more (300 merchants, a tag on
/// one in seven), what 記一筆 reads (merchants, lastUsedOn, lastAt, usual,
/// usualTransfers) and all eight are gated, each right after a save, as
/// shares of the old one pass over every entry each, the least of
/// [gateTries] runs, so they hold on any machine. With `BENCH=1` the
/// times are printed.
void main() {
  final bench = Platform.environment['BENCH'] != null;

  test('a save counts its month again, not the book', () async {
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
          merchant: '店${i % 300}',
          tags: i % 7 == 0 ? const ['家用'] : const [],
        ),
    ]);
    var saved = 0;
    void save() => ledger.entryCommands.add(
      Entry(
        id: 'n${saved++}',
        date: today,
        type: EntryType.expense,
        amount: 50,
        account: accounts.first,
        category: spending.first,
        merchant: '店1',
      ),
    );
    final queries = ledger.entryQueryService;
    final reports = ledger.reportService;
    void composer() {
      queries.merchants;
      queries.lastUsedOn;
      queries.lastAt('店1');
      queries.usual();
      queries.usualTransfers();
    }

    void all() {
      composer();
      reports.tagStats;
      reports.merchantStats;
      reports.tags;
    }

    Future<int> timed(void Function() run, {bool saving = false}) =>
        leastOf(gateTries, () async {
          if (saving) save();
          final watch = Stopwatch()..start();
          run();
          return watch.elapsedMicroseconds;
        });

    final before = WholeBookReads(ledger);
    void oldComposer() {
      before.merchants();
      before.lastUsedOn();
      before.lastAt();
      before.usual();
      before.usualTransfers();
    }

    final oldFive = await timed(oldComposer);
    final oldEight = await timed(() {
      oldComposer();
      before.tagStats();
      before.merchantStats();
      before.tags();
    });
    // Warmed up, as the old reads were by their own runs: every month
    // counted once, then a few saves read after.
    for (var i = 0; i < _warmUps; i++) {
      save();
      all();
    }

    final five = await timed(composer, saving: true);
    final eight = await timed(all, saving: true);
    expect(reports.merchantStats, before.merchantStats());
    expect(queries.merchants, before.merchants());
    if (bench) {
      // ignore: avoid_print
      print(
        '記一筆 old $oldFive µs, after a save $five µs; '
        'all eight old $oldEight µs, after a save $eight µs',
      );
    }
    expect(
      five / oldFive,
      lessThanOrEqualTo(_composerMost),
      reason:
          '記一筆\'s reads after a save took $five µs, one pass over every '
          'entry each $oldFive µs',
    );
    expect(
      eight / oldEight,
      lessThanOrEqualTo(_allMost),
      reason:
          'the eight reads after a save took $eight µs, one pass over every '
          'entry each $oldEight µs',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// The saves read after before any is timed.
const _warmUps = 5;

/// The largest share of the old reads 記一筆's may take after a save:
/// about twice the largest measured (thresholds.md).
const _composerMost = 0.28;

/// The largest share all eight may take after a save.
const _allMost = 0.27;
