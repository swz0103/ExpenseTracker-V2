import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/journal_rebuild.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/write_batch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

/// A book of [splitOpeningFrom] entries or more opens with its entries
/// decoded half on the opening's worker and half on a second one, when
/// there is a core for it: the two halves come back as one book, in
/// order. (How long it takes is the timing gates', test/perf.)
void main() {
  test(
    'a large book opened on two workers comes back whole and in order',
    () async {
      expect(splitOpeningFrom, 20000);
      final today = DateTime.utc(2026, 10, 4);
      final dir = Directory.systemTemp.createTempSync('split-open-');
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
      final account = first.accounts.main;
      const count = 20001;
      await source.keep(
        WriteBatch(
          entries: [
            for (var i = 0; i < count; i++)
              Entry(
                id: 'e$i',
                date: today.subtract(Duration(days: i % 1000)),
                type: EntryType.expense,
                amount: 100 + i,
                account: account,
                category: '飲食日常',
              ),
          ],
        ),
      );
      final opened = await SqlLedgerDataSource(
        store,
        clock: FixedClock(UtcInstant(today)),
      ).load();
      final byId = {for (final e in opened.entries.all) e.id: e};
      expect(byId, hasLength(count));
      // The first of the first half, the last of it, the first of the
      // second half (20,001 ~/ 2 = 10,000) and the last of all.
      for (final i in [0, 9999, 10000, 20000]) {
        expect(byId['e$i']!.amount, 100 + i);
      }
    },
  );
}
