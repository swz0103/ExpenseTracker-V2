/// A merchant renamed on 20,000 entries does not hold the screen still
/// (DAT-03): the rows are made a slice at a time and kept on a worker
/// isolate. Measured as the longest the isolate is held, against the
/// same rename written at once, so it holds on any machine; judged on
/// interleaved pairs the host did not stall (held.dart, `shareOf`); the
/// limit and how it was measured are in thresholds.md
/// (`batch_write_block`).
@Tags(['timing'])
library;

import 'dart:io';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/write_batch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

import '../support/held.dart';

void main() {
  /// The longest the isolate may be held, as a share of the whole rename
  /// written at once: twice the worst of the measured runs.
  const limit = 0.045;

  /// A book of [count] entries at 全聯, on [source].
  Future<Ledger> book(SqlLedgerDataSource source, int count) async {
    final ledger = await source.load();
    final account = ledger.accounts.all.first.id;
    await source.keep(
      WriteBatch(
        entries: [
          for (var i = 0; i < count; i++)
            Entry(
              id: 'e$i',
              date: DateTime.utc(2024, 1 + i % 12, 1 + i % 28),
              type: EntryType.expense,
              amount: 100 + i,
              account: account,
              category: '飲食日常',
              merchant: '全聯',
              note: 'n$i',
            ),
        ],
      ),
    );
    return source.load();
  }

  /// Renames the merchant of every entry of a fresh book of 20,000, kept
  /// apart from [apartFrom] records; the longest the isolate was held.
  Future<Held<void>> rename(int apartFrom) async {
    final dir = Directory.systemTemp.createTempSync('batch-write-');
    final store = EncryptedDatabase.open(
      File('${dir.path}/l.db'),
      StorageKey.random(),
    );
    try {
      final source = SqlLedgerDataSource(store, writeApartFrom: apartFrom);
      final ledger = await book(source, 20000);
      final revision = store.revision;
      final held = await timeHeld(() async {
        ledger.entryCommands.renameMerchant('全聯', '全聯福利中心');
        await ledger.settled;
      });
      // Every entry renamed on disk, in one change of the book.
      expect(
        store.rows(shelf: 'entry').where((r) => r.body.contains('全聯福利中心')),
        hasLength(20000),
      );
      expect(store.revision, revision + 1);
      return held;
    } finally {
      store.close();
      dir.deleteSync(recursive: true);
    }
  }

  test('renaming a merchant on 20,000 entries holds the screen for a '
      'small share of the rename written at once', () async {
    // Warm up both paths first, so neither is charged for compiling.
    await rename(1 << 30);
    await rename(writeApartFrom);
    // Interleaved pairs, the one apart first in each (held.dart).
    final result = await shareOf(
      apart: () => rename(writeApartFrom),
      whole: () => rename(1 << 30),
      limit: limit,
    );
    expectShare(result, 'batch_write_block');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
