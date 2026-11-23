// Work package 2.1: loading tolerates bad rows and keeps renames on disk.
// Fixed in 2.1: these run in every test run (STATUS.md).
import 'dart:convert';
import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_json.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

void main() {
  late Directory directory;
  late EncryptedDatabase store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('p2-1-');
    store = EncryptedDatabase.open(
      File('${directory.path}/ledger.db'),
      StorageKey.random(),
    );
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Entry entry(int i) => Entry(
    id: 'e$i',
    date: DateTime.utc(2026, 1, 1),
    type: EntryType.expense,
    amount: 100 + i,
    account: 'x',
  );

  for (final bad in ['{not json', '{"id":"zz","_v":99}', '[1,2]']) {
    test(
      'DAT-01: one unreadable row ($bad) does not stop the other 100 loading',
      () async {
        // Let the data source create its first-run records, then add 100
        // good entries and one bad row.
        await SqlLedgerDataSource(store).load();
        store.write((w) {
          for (var i = 0; i < 100; i++) {
            w.put('entry', 'e$i', jsonEncode(entryToJson(entry(i))));
          }
          w.put('entry', 'bad', bad);
        });
        final ledger = await SqlLedgerDataSource(store).load();
        expect(ledger.entries.all, hasLength(100));
        // The bad row is kept on disk, not deleted.
        expect(store.rows(shelf: 'entry'), hasLength(101));
      },
    );
  }

  test('DAT-05: renaming a category is kept for the entries on disk', () async {
    final clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 4, 4)));
    var ledger = await SqlLedgerDataSource(store, clock: clock).load();
    ledger.entryCommands.add(
      Entry(
        id: ledger.newId(),
        date: DateTime.utc(2026, 10, 2),
        type: EntryType.expense,
        amount: 5,
        account: ledger.accounts.all.first.id,
        category: '寵物',
      ),
    );
    ledger.categoryCommands.addCategory(Category('寵物', 'pet', 0xFF123456));
    ledger.categoryCommands.updateCategory(
      '寵物',
      ledger.category('寵物').copyWith(name: '毛孩'),
    );
    await ledger.settled;
    ledger = await SqlLedgerDataSource(store, clock: clock).load();
    expect(ledger.entries.all.single.category, '毛孩');
  });
}
