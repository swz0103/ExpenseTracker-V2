@Tags(['timing'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/market_days.dart';
import 'package:expense_tracker/src/core/ledger/persistence/market_rows.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/write_batch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

import '../support/held.dart';

/// Opening a book of 100,000 entries with five years of market history
/// kept (PERF-4): the months long gone are folded into a row each
/// (review 39) on the book's worker, and the fold is kept after the
/// opening, never on its way. Kept on its way, it waited for the
/// journal's posting of the whole book afresh, on the worker, to let go
/// of the store: 2.9 s against 1.5 s for the same book with nothing to
/// fold (a share of 1.9; host, two cores); 1.03–1.08 once kept after.
///
/// Gated as a share: the least of [gateTries] openings with a fold to
/// keep against the least of as many with none, the journal posted
/// afresh at each; and the fold is kept once the opening is done.
void main() {
  final today = DateTime.utc(2026, 10, 4);
  final day0 = BusinessDate.of(today);

  test('a large book with five years of market history opens without '
      'waiting for its fold', () async {
    final dir = Directory.systemTemp.createTempSync('market-open-');
    final store = EncryptedDatabase.open(
      File('${dir.path}/l.db'),
      StorageKey.random(),
    );
    addTearDown(() {
      store.close();
      dir.deleteSync(recursive: true);
    });
    final first = await SqlLedgerDataSource(
      store,
      clock: FixedClock(UtcInstant(today)),
    ).load();
    final accounts = [for (final a in first.accounts.all) a.id];
    final spending = [
      for (final c in first.categories.forEntries(income: false)) c.name,
    ];
    const count = 100000;
    await SqlLedgerDataSource(store, clock: FixedClock(UtcInstant(today))).keep(
      WriteBatch(
        entries: [
          for (var i = 0; i < count; i++)
            Entry(
              id: 'e$i',
              date: today.subtract(Duration(days: (count - i) * 1095 ~/ count)),
              type: EntryType.expense,
              amount: 40 + i * 37 % 900,
              account: accounts[i % accounts.length],
              category: spending[i % spending.length],
            ),
        ],
      ),
    );

    // Every weekday of five years, as a busy book keeps them: 19
    // currencies' buying and selling rates and 15 closes. Written again
    // before each opening with a fold to keep.
    void keepDays() => store.write((w) {
      for (var i = 0; i < 5 * 365; i++) {
        final day = day0.addDays(-i);
        if (day.isWeekend) continue;
        w.put(
          marketShelf,
          marketDayId(day),
          jsonEncode({
            'rates': {for (var c = 0; c < 19; c++) 'C$c': 30 + c + i / 1000},
            'sell': {for (var c = 0; c < 19; c++) 'C$c': 31 + c + i / 1000},
            'closes': {for (var s = 0; s < 15; s++) '${1000 + s}': 100 + i},
          }),
        );
      }
    }, counts: false);

    var folded = 0;
    Future<int> open({required bool fold}) async {
      if (fold) keepDays();
      // An entry changed, so the journal is posted afresh as the book
      // opens, holding the store on the worker for its length.
      await SqlLedgerDataSource(
        store,
        clock: FixedClock(UtcInstant(today)),
      ).keep(
        WriteBatch(
          entries: [
            Entry(
              id: 'e0',
              date: today,
              type: EntryType.expense,
              amount: 41 + folded++,
              account: accounts.first,
              category: spending.first,
            ),
          ],
        ),
      );
      final source = SqlLedgerDataSource(
        store,
        clock: FixedClock(UtcInstant(today)),
        keepsJournal: true,
      );
      final watch = Stopwatch()..start();
      await source.load();
      final us = watch.elapsedMicroseconds;
      await source.journal.settled;
      await source.folding;
      // Kept once the opening is done: about 286 weekdays of the last
      // 400 days and a row for each month before, not 1,300 days.
      expect(store.rows(shelf: marketShelf).length, lessThan(400));
      return us;
    }

    final none = await leastOf(gateTries, () => open(fold: false));
    final withFold = await leastOf(gateTries, () => open(fold: true));
    // ignore: avoid_print
    print(
      'MARKET OPEN with a fold ${withFold ~/ 1000} ms, '
      'none ${none ~/ 1000} ms',
    );
    expect(
      withFold / none,
      lessThanOrEqualTo(_most),
      reason: 'with a fold $withFold µs, with none $none µs',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// The largest share of an opening with nothing to fold that one with a
/// fold may take (thresholds.md, "PERF-4").
const _most = 1.4;
