import 'dart:async';
import 'dart:io';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/write_batch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

/// The store's own work at scale: a book of 100,000 entries filled, one
/// and fifty entries kept, and the book opened, with the longest the
/// screen is held still while it opens. Slow, so it only runs when asked:
/// `BENCH=1 flutter test test/perf/open_bench_test.dart`.
void main() {
  final asked = Platform.environment['BENCH'] != null;
  test(
    'writes and opening at 100,000 entries',
    () async {
      final dir = Directory.systemTemp.createTempSync('wb-');
      final store = RowStore.open(
        File('${dir.path}/l.db'),
        StorageKey.random(),
      );
      final source = SqlLedgerDataSource(store);
      Entry e(int i) => Entry(
        id: 'e$i',
        date: DateTime.utc(2024, 1 + i % 12, 1 + i % 28),
        type: EntryType.expense,
        amount: 100 + i,
        account: 'bank',
        category: '飲食',
        merchant: '店${i % 300}',
        note: 'n$i',
      );
      final sw0 = Stopwatch()..start();
      for (var k = 0; k < 10; k++) {
        await source.keep(
          WriteBatch(
            entries: [for (var i = k * 10000; i < (k + 1) * 10000; i++) e(i)],
          ),
        );
      }
      // ignore: avoid_print
      print('FILL 100k ${sw0.elapsedMilliseconds} ms');
      for (final n in [1, 50]) {
        final t = <int>[];
        for (var r = 0; r < 15; r++) {
          final sw = Stopwatch()..start();
          await source.keep(
            WriteBatch(
              entries: [for (var i = 0; i < n; i++) e(200000 + r * 100 + i)],
            ),
          );
          t.add(sw.elapsedMicroseconds);
        }
        t.sort();
        // ignore: avoid_print
        print(
          'WRITE $n entries: median ${(t[7] / 1000).toStringAsFixed(2)} ms, worst ${(t.last / 1000).toStringAsFixed(2)} ms',
        );
      }
      final r0 = Stopwatch()..start();
      final rows = store.rows().toList();
      // ignore: avoid_print
      print(
        'ONE READ OF ALL ${rows.length} rows, as opening did before: '
        '${r0.elapsedMilliseconds} ms',
      );
      var worst = 0;
      final tick = Stopwatch()..start();
      var last = 0;
      final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
        final now = tick.elapsedMilliseconds;
        if (now - last > worst) worst = now - last;
        last = now;
      });
      final sw = Stopwatch()..start();
      final loaded = await SqlLedgerDataSource(store).load();
      timer.cancel();
      // ignore: avoid_print
      print('LONGEST BLOCK $worst ms');
      // ignore: avoid_print
      print(
        'LOAD ${loaded.entries.all.length} in ${sw.elapsedMilliseconds} ms',
      );
      store.close();
      dir.deleteSync(recursive: true);
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: !asked,
  );
}
