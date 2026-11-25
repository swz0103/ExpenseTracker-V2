/// Posting the whole journal afresh does not hold the screen still
/// (decision D51): it is read, posted and written on worker isolates.
/// Measured as the longest the isolate is held, against the same book
/// posted afresh on it at once, so it holds on any machine; judged on
/// interleaved pairs the host did not stall (held.dart, `shareOf`). The
/// limit and how it was measured are in thresholds.md
/// (`journal_rebuild_block`).
@Tags(['timing'])
library;

import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/journal/book_mapping.dart';
import 'package:expense_tracker/src/core/ledger/journal/replay.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/journal_keeper.dart';
import 'package:expense_tracker/src/core/ledger/persistence/journal_rebuild.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/write_batch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kernel/kernel.dart';
import 'package:storage/storage.dart';

import '../support/held.dart';

void main() {
  /// The longest the isolate may be held, as a share of the book posted
  /// at once (thresholds.md, `journal_rebuild_block`).
  const limit = 0.045;

  /// Entries in the book: posting at once grows with them, the hold
  /// apart (a slice of the work) does not, so the share has room.
  const count = 50000;

  final today = DateTime.utc(2026, 10, 4);
  final key = StorageKey.random();
  final template = Directory.systemTemp.createTempSync('journal-gate-');
  tearDownAll(() => template.deleteSync(recursive: true));

  /// The book of [count] entries, spending, transfers and trades, kept
  /// once in [template]; each run opens a copy of its file.
  Future<void> keepTemplate() async {
    final store = EncryptedDatabase.open(File('${template.path}/l.db'), key);
    final source = SqlLedgerDataSource(
      store,
      clock: FixedClock(UtcInstant(today)),
    );
    final ledger = await source.load();
    final bank = ledger.accounts.main;
    final cash = ledger.accounts.all.firstWhere((a) => a.id != bank).id;
    await source.keep(
      WriteBatch(
        entries: [
          for (var i = 0; i < count; i++)
            Entry(
              id: 'e$i',
              date: today.subtract(Duration(days: i % 1800)),
              type: switch (i % 10) {
                0 => EntryType.buy,
                1 => EntryType.transfer,
                _ => EntryType.expense,
              },
              amount: 100 + i % 900,
              account: bank,
              to: i % 10 == 1 ? cash : null,
              category: '飲食日常',
              holding: i % 10 == 0 ? '2330' : null,
              shares: i % 10 == 0 ? 1 : 0,
            ),
        ],
      ),
    );
    store.close();
  }

  /// A copy of the template's book, open.
  Future<(EncryptedDatabase, Ledger, Directory)> book() async {
    final dir = Directory.systemTemp.createTempSync('journal-gate-');
    for (final f in template.listSync().whereType<File>()) {
      f.copySync('${dir.path}/${f.uri.pathSegments.last}');
    }
    final store = EncryptedDatabase.open(File('${dir.path}/l.db'), key);
    final source = SqlLedgerDataSource(
      store,
      clock: FixedClock(UtcInstant(today)),
    );
    return (store, await source.load(), dir);
  }

  Future<Held<void>> atOnce() async {
    final (store, ledger, dir) = await book();
    try {
      final mapping = BookMapping(
        accounts: ledger.accounts.all,
        categories: ledger.categories.all,
      );
      final seqs = {
        for (final r in store.rows(shelf: Collection.entry.name)) r.id: r.seq,
      };
      return await timeHeld(() async {
        await replayBook(
          mapping: mapping,
          journal: Journal(
            registry: registryFor(() => mapping),
            accounts: AccountTree(),
            store: store.journal,
            source: (_) => null,
          ),
          store: store.journal,
          entries: [
            for (final e in ledger.entries.all) (entry: e, seq: seqs[e.id]!),
          ],
          chunk: 1 << 30,
        );
      });
    } finally {
      store.close();
      dir.deleteSync(recursive: true);
    }
  }

  Future<Held<void>> apart() async {
    final (store, ledger, dir) = await book();
    try {
      final block = await timeHeld(
        () => store.postApart(
          postingWork(aside: const {}, start: const []),
          mark: (rules: journalRules, revision: store.revision),
        ),
      );
      expect(
        store.journal.intentCount,
        ledger.entries.all.length,
        reason: 'every entry posted',
      );
      expect(store.journal.mark!.revision, store.revision);
      return block;
    } finally {
      store.close();
      dir.deleteSync(recursive: true);
    }
  }

  test('posting the whole journal afresh holds the screen for a small '
      'share of posting it at once', () async {
    await keepTemplate();
    // Warm up both paths first, so neither is charged for compiling.
    await atOnce();
    await apart();
    // Interleaved pairs, the worker first in each: posting at once here
    // leaves a heap of this isolate's own to be collected, which the app
    // never has before its rebuild. Whole collections of the workers'
    // garbage stop this isolate too, at their own times: the median of
    // the clean pairs' ratios is judged, not one sample.
    final result = await shareOf(apart: apart, whole: atOnce, limit: limit);
    expectShare(result, 'journal_rebuild_block');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
