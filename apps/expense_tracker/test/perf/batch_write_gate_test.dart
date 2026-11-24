import 'dart:async';
import 'dart:io';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/write_batch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

import '../support/held.dart';

/// A merchant renamed on 20,000 entries does not hold the screen still
/// (DAT-03): the rows are made a slice at a time and kept on a worker
/// isolate. Measured as the longest the isolate is held, against the
/// same rename written at once, so it holds on any machine; the limit
/// and how it was measured are in thresholds.md (`batch_write_block`).
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
  /// apart from [apartFrom] records; the longest the isolate was held
  /// and the whole time, in milliseconds.
  Future<({int block, int total})> rename(int apartFrom) async {
    final dir = Directory.systemTemp.createTempSync('batch-write-');
    final store = EncryptedDatabase.open(
      File('${dir.path}/l.db'),
      StorageKey.random(),
    );
    try {
      final source = SqlLedgerDataSource(store, writeApartFrom: apartFrom);
      final ledger = await book(source, 20000);
      final revision = store.revision;
      final tick = Stopwatch()..start();
      var last = 0;
      var block = 0;
      final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
        final now = tick.elapsedMilliseconds;
        if (now - last > block) block = now - last;
        last = now;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      block = 0;
      final watch = Stopwatch()..start();
      ledger.entryCommands.renameMerchant('全聯', '全聯福利中心');
      await ledger.settled;
      final total = watch.elapsedMilliseconds;
      // The tick after the last hold, before the timer stops.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      timer.cancel();
      // Every entry renamed on disk, in one change of the book.
      expect(
        store.rows(shelf: 'entry').where((r) => r.body.contains('全聯福利中心')),
        hasLength(20000),
      );
      expect(store.revision, revision + 1);
      return (block: block, total: total);
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
    // The least of a few runs each, the one apart first (held.dart).
    final apart = await _least(() => rename(writeApartFrom));
    final atOnce = await _least(() => rename(1 << 30));
    final share = apart.block / atOnce.block;
    // ignore: avoid_print
    print(
      'batch_write_block: at once ${atOnce.block} ms held '
      '(${atOnce.total} ms in all); apart ${apart.block} ms held '
      '(${apart.total} ms in all); share ${share.toStringAsFixed(3)}',
    );
    expect(share, lessThanOrEqualTo(limit));
  }, timeout: const Timeout(Duration(minutes: 6)));
}

/// The run of [rename] that held the isolate least, of [gateTries].
Future<({int block, int total})> _least(
  Future<({int block, int total})> Function() rename,
) async {
  final blocks = <int, ({int block, int total})>{};
  final least = await leastOf(gateTries, () async {
    final r = await rename();
    blocks[r.block] = r;
    return r.block;
  });
  return blocks[least]!;
}
