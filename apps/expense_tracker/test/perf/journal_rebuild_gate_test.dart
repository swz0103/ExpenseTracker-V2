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

/// Posting the whole journal afresh does not hold the screen still
/// (decision D51): it is read, posted and written on worker isolates.
/// Measured as the longest the isolate is held, against the same book
/// posted afresh on it at once, so it holds on any machine; the limit is
/// the one the batch writes keep (batch_write_gate_test.dart, 0.045).
void main() {
  /// The longest the isolate may be held, as a share of the book posted
  /// at once.
  const limit = 0.045;
  final today = DateTime.utc(2026, 10, 4);

  /// A book of 20,000 entries, spending, transfers and trades.
  Future<(EncryptedDatabase, Ledger, Directory)> book() async {
    final dir = Directory.systemTemp.createTempSync('journal-gate-');
    final store = EncryptedDatabase.open(
      File('${dir.path}/l.db'),
      StorageKey.random(),
    );
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
          for (var i = 0; i < 20000; i++)
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
    return (store, await source.load(), dir);
  }

  /// The longest the isolate was held while [run] ran, in microseconds.
  Future<int> held(Future<void> Function() run) async =>
      (await timeHeld(run)).heldUs;

  Future<int> atOnce() async {
    final (store, ledger, dir) = await book();
    try {
      final mapping = BookMapping(
        accounts: ledger.accounts.all,
        categories: ledger.categories.all,
      );
      final seqs = {
        for (final r in store.rows(shelf: Collection.entry.name)) r.id: r.seq,
      };
      return await held(() async {
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

  Future<int> apart() async {
    final (store, ledger, dir) = await book();
    try {
      final block = await held(
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
    // Warm up both paths first, so neither is charged for compiling.
    await atOnce();
    await apart();
    final whole = await atOnce();
    final worker = await apart();
    final share = worker / whole;
    // ignore: avoid_print
    print(
      'journal_rebuild_block: at once ${whole ~/ 1000} ms held; apart '
      '${worker ~/ 1000} ms held; share ${share.toStringAsFixed(3)}',
    );
    expect(share, lessThanOrEqualTo(limit));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
