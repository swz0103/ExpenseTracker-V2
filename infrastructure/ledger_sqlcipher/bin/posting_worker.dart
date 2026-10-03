import 'dart:io';

import 'package:bookkeeping/bookkeeping.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';

/// Usage: posting_worker <database> <hex key> <workspace> <first account>
/// <second account> <count>
///
/// Books [count] entries between the two TWD accounts: income, expenses,
/// transfers and reversals of earlier ones. Prints `committed <n>` after
/// every commit so a test can kill it mid-stream (health check G5-03).
///
/// Usage: posting_worker migrate <database> <hex key>
///
/// Upgrades the ledger to the current schema and then runs one long extra
/// step from [bulkSchema], printing `migrating` first, so a test can kill
/// it in the middle of a migration (health check G6-09).
Future<void> main(List<String> args) async {
  if (args.length == 3 && args[0] == 'migrate') {
    stdout.writeln('migrating');
    await stdout.flush();
    final store = SqlCipherStore.open(
      File(args[1]),
      StorageKey.fromHex(args[2]),
      modules: [ledgerSchema, bulkSchema],
    );
    store.close();
    stdout.writeln('migrated');
    await stdout.flush();
    return;
  }
  if (args.length != 6) exit(64);
  final store = SqlCipherStore.open(
    File(args[0]),
    StorageKey.fromHex(args[1]),
    modules: [ledgerSchema],
  );
  final ledger = LedgerStore(store);
  final books = Bookkeeping(ledger);
  final workspace = WorkspaceId.parse(args[2]);
  final first = PublicId.parse(args[3]);
  final second = PublicId.parse(args[4]);
  final count = int.parse(args[5]);
  final twd = Currency.of('TWD');
  final date = BusinessDate(2026, 10, 1);
  final booked = <PublicId>[];
  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
  AccountRef ref(PublicId id) {
    final account = ledger.accounts(workspace).singleWhere((a) => a.id == id);
    return AccountRef(id, account.rulesVersion);
  }

  for (var i = 0; i < count; i++) {
    final id = PublicId.generate();
    final amount = Money(twd, BigInt.from(1 + i % 97));
    switch (i % 4) {
      case 0 || 1:
        await books.recordCashFlow(
          RecordCashFlow(
            operation: op(),
            postingId: id,
            flow: i.isEven ? CashFlow.income : CashFlow.expense,
            account: ref(i % 3 == 0 ? first : second),
            date: date,
            amount: amount,
          ),
        );
        booked.add(id);
      case 2:
        await books.recordTransfer(
          RecordTransfer(
            operation: op(),
            postingId: id,
            source: ref(first),
            destination: ref(second),
            date: date,
            principal: amount,
            fee: Money(twd, BigInt.one),
          ),
        );
      default:
        await books.reversePosting(
          ReversePosting(
            operation: op(),
            reversalId: id,
            originalId: booked.removeLast(),
            date: date,
          ),
        );
    }
    stdout.writeln('committed $i');
  }
  await stdout.flush();
  store.close();
}

/// One migration step long enough to be killed part way.
final bulkSchema = SchemaModule('bulk', [
  [
    'CREATE TABLE bulk_rows (n INTEGER PRIMARY KEY, pad TEXT NOT NULL)',
    '''
    INSERT INTO bulk_rows
    WITH RECURSIVE c(n) AS (
      SELECT 1 UNION ALL SELECT n + 1 FROM c LIMIT $bulkRows
    )
    SELECT n, hex(randomblob(32)) FROM c
    ''',
  ],
]);

/// Kept in step with `crash_test.dart`.
const bulkRows = 2000000;
