@Tags(['timing'])
library;

import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/journal_keeper.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/write_batch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

import '../support/held.dart';

/// Opening a book of 100,000 entries is done on its worker (D51): the
/// screen's isolate only spawns it, takes the book back and makes the
/// ledger of it. Two shares of the opening gate that, so they hold on any
/// machine and core count (thresholds.md, "Opening a large book"):
///
/// - the longest the screen's isolate is held while the book opens;
/// - the time the opening spends outside the worker's own work (starting
///   it, handing the book back, and all done here after): the part that
///   grows with what the worker hands back and what this isolate does
///   with it, which a phone of two cores feels most.
///
/// The worker's own time is gated too, against a figure measured on the
/// development host (`workerLimitUs`); and what the two ways of making it
/// shorter leave in the book is checked as it is, not by its time, so
/// losing either fails here whatever the machine's load (review 24):
///
/// - with a core beside the worker's, half of the entries were decoded
///   on a second worker (`lastOpening.split`);
/// - what entries repeat is one object for the book (`SameValues`): as
///   many accounts, notes, merchants and days as there are values, not
///   one per entry.
///
/// Each share and the worker's time is the least of [gateTries] runs.
/// The book is then opened once more as the app opens it, with the
/// journal kept: sent to this isolate as soon as it is read, and posted
/// afresh on the worker. Pinned to two cores (`taskset -c 0,1 flutter
/// test test/perf/open_gate_test.dart`) it is the host's stand-in for the
/// emulator bench's `100k_load_ms`.
void main() {
  /// The longest the screen's isolate may be held, as a share of the
  /// opening.
  const heldLimit = 0.08;

  /// The most of the opening that may be spent outside the worker's work.
  const outsideLimit = 0.06;

  /// The longest the worker may take to read the book, in microseconds:
  /// about twice the least measured on the development host
  /// (thresholds.md).
  const workerLimitUs = 2600000;

  final today = DateTime.utc(2026, 10, 4);

  test('a book of 100,000 entries opens on its worker', () async {
    final dir = Directory.systemTemp.createTempSync('open-gate-');
    final store = EncryptedDatabase.open(
      File('${dir.path}/l.db'),
      StorageKey.random(),
    );
    addTearDown(() {
      store.close();
      dir.deleteSync(recursive: true);
    });
    final source = SqlLedgerDataSource(
      store,
      clock: FixedClock(UtcInstant(today)),
    );
    final first = await source.load();
    final accounts = [for (final a in first.accounts.all) a.id];
    final spending = [
      for (final c in first.categories.forEntries(income: false)) c.name,
    ];
    // As the emulator bench fills its book: three years, a salary in
    // thirty, a note on every other entry, a tag on every seventh.
    const count = 100000;
    await source.keep(
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
              note: i.isEven ? '午餐' : '',
              tags: i % 7 == 0 ? const ['家用'] : const [],
            ),
        ],
      ),
    );
    // A second worker is started only with a core beside the worker's.
    final splits = Platform.numberOfProcessors > 1;

    // The whole opening, as the app does it, the longest hold, and the
    // worker's part of it, as the data source timed it; each share the
    // least of [gateTries] openings.
    final openings = <_Opening>[];
    for (var i = 0; i < gateTries; i++) {
      final held = await timeHeld(() async {
        final ledger = await source.load();
        expect(ledger.entries.length, count);
        if (i == 0) _expectShared(ledger.entries.all);
      });
      final (:us, :workerUs, :split) = source.lastOpening!;
      expect(split, splits, reason: 'half the entries on a second worker');
      openings.add(_Opening(us, workerUs!, held.heldUs));
    }
    double least(double Function(_Opening o) share) =>
        openings.map(share).reduce((a, b) => a < b ? a : b);
    final held = least((o) => o.held);
    final outside = least((o) => o.outside);
    final worker = least((o) => o.workerUs.toDouble()).round();

    // As the app opens it: the journal kept, the book sent here as soon
    // as it is read, then posted afresh on the worker.
    final kept = SqlLedgerDataSource(
      store,
      clock: FixedClock(UtcInstant(today)),
      keepsJournal: true,
    );
    final ledger = await kept.load();
    expect(ledger.entries.length, count);
    _expectShared(ledger.entries.all);
    final keptOpening = kept.lastOpening!;
    expect(keptOpening.split, splits);
    await kept.journal.settled;
    expect(store.journal.mark, (rules: journalRules, revision: store.revision));
    expect(store.journal.intentCount, count, reason: 'every entry posted');

    // ignore: avoid_print
    print(
      'OPEN 100k ${[for (final o in openings) o.us ~/ 1000]} ms, worker '
      '${[for (final o in openings) o.workerUs ~/ 1000]} ms, held '
      '${[for (final o in openings) o.heldUs ~/ 1000]} ms; held share '
      '${held.toStringAsFixed(3)}, outside share '
      '${outside.toStringAsFixed(3)}; split $splits; with the journal '
      '${keptOpening.us ~/ 1000} ms, worker ${keptOpening.workerUs! ~/ 1000} '
      'ms',
    );
    expect(held, lessThan(heldLimit), reason: 'the screen held');
    expect(outside, lessThan(outsideLimit), reason: 'outside the worker');
    expect(worker, lessThan(workerLimitUs), reason: "the worker's own time");
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// What [entries] repeat is one object for each value (`SameValues`):
/// as many accounts, notes, merchants, tags and days as there are
/// values, not one for each entry.
void _expectShared(List<Entry> entries) {
  void one<T extends Object>(String what, Iterable<T> values) {
    final kept = Set<T>.identity()..addAll(values);
    expect(kept.length, values.toSet().length, reason: '$what shared');
  }

  one('accounts', entries.map((e) => e.account));
  one('notes', entries.map((e) => e.note));
  one('merchants', entries.map((e) => e.merchant));
  one('tags', entries.expand((e) => e.tags));
  one('days', entries.map((e) => e.date));
}

/// One opening: its time, the worker's part of it and the longest hold,
/// in microseconds.
final class _Opening {
  const _Opening(this.us, this.workerUs, this.heldUs);

  final int us;
  final int workerUs;
  final int heldUs;

  /// The longest hold, as a share of the opening.
  double get held => heldUs / us;

  /// The share of the opening spent outside the worker's work.
  double get outside => (us - workerUs) / us;
}
