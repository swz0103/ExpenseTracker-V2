import 'dart:io';
import 'dart:math';

import 'package:accounts/accounts.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

/// About three years of daily use: 10,000 commands through the full
/// bookkeeping pipeline, then reads and a full replay.
const _commands = 10000;

void main() {
  test('10k real commands stay fast to write, read and replay', () async {
    final directory = Directory.systemTemp.createTempSync('ledger-scale-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final workspace = WorkspaceId(PublicId.generate());
    final twd = Currency.of('TWD');
    Money ntd(int units) => Money(twd, BigInt.from(units));
    OperationKey op() =>
        OperationKey(workspace, OperationId(PublicId.generate()));
    final store = SqlCipherStore.open(
      File('${directory.path}/ledger.db'),
      StorageKey.random(),
      modules: [ledgerSchema],
    );
    addTearDown(store.close);
    final ledger = LedgerStore(store);
    final books = Bookkeeping(ledger);

    final accounts = <PublicId>[];
    for (final name in ['現金', '薪轉', '儲蓄']) {
      final id = PublicId.generate();
      await books.openAccount(
        OpenAccount(
          operation: op(),
          accountId: id,
          name: name,
          kind: AccountKind.bank,
          currency: twd,
          openedOn: BusinessDate(2024, 1, 1),
          openingBalance: ntd(10000000),
          openingPostingId: PublicId.generate(),
        ),
      );
      accounts.add(id);
    }
    final categories = <PublicId>[];
    for (final name in ['餐飲', '交通', '購物', '居家', '娛樂']) {
      final id = PublicId.generate();
      await books.changeCatalog(
        ChangeCatalog(
          operation: op(),
          catalog: CatalogType.category,
          change: CreateEntry(id, name, kind: CategoryKind.expense),
        ),
      );
      categories.add(id);
    }

    final random = Random(42);
    final recorded = <PublicId>[];
    final latencies = <int>[];
    final write = Stopwatch()..start();
    for (var i = 0; i < _commands; i++) {
      final date = BusinessDate(2024 + i ~/ 3400, 1 + (i ~/ 280) % 12, 1);
      final account = accounts[random.nextInt(accounts.length)];
      final watch = Stopwatch()..start();
      final roll = random.nextInt(100);
      if (roll < 8) {
        final other = accounts[(accounts.indexOf(account) + 1) % 3];
        await books.recordTransfer(
          RecordTransfer(
            operation: op(),
            postingId: PublicId.generate(),
            source: AccountRef(account, 1),
            destination: AccountRef(other, 1),
            date: date,
            principal: ntd(1 + random.nextInt(50000)),
          ),
        );
      } else if (roll < 10 && recorded.isNotEmpty) {
        try {
          await books.reversePosting(
            ReversePosting(
              operation: op(),
              reversalId: PublicId.generate(),
              originalId: recorded.removeAt(random.nextInt(recorded.length)),
              date: BusinessDate(2027, 1, 1),
            ),
          );
        } on Object {
          // Already reversed; fine for a load test.
        }
      } else {
        final amount = 100 + random.nextInt(100000);
        final category = categories[random.nextInt(categories.length)];
        final outcome = await books.recordCashFlow(
          RecordCashFlow(
            operation: op(),
            postingId: PublicId.generate(),
            flow: CashFlow.expense,
            account: AccountRef(account, 1),
            date: date,
            amount: ntd(amount),
            allocations: [CategoryShare(category, 1, ntd(amount))],
          ),
        );
        recorded.add(outcome.value);
      }
      latencies.add(watch.elapsedMicroseconds);
    }
    write.stop();
    latencies.sort();
    final index = latencies.length * 95 ~/ 100;
    final p95 = Duration(microseconds: latencies[index]);

    final read = Stopwatch()..start();
    for (final id in accounts) {
      ledger.balance(ledger.accounts(workspace).singleWhere((a) => a.id == id));
    }
    final month = ledger.monthly(workspace, '2025-06');
    final byCategory = ledger.categoryTotals(workspace, '2025-06');
    read.stop();

    final copy = SqlCipherStore.open(
      File('${directory.path}/copy.db'),
      StorageKey.random(),
      modules: [ledgerSchema],
    );
    addTearDown(copy.close);
    final replay = Stopwatch()..start();
    await LedgerReplay.copy(from: store, to: LedgerStore(copy));
    replay.stop();

    print(
      'scale: $_commands commands in ${write.elapsed.inMilliseconds} ms, '
      'p95 ${p95.inMicroseconds} us, reads ${read.elapsedMicroseconds} us, '
      'replay ${replay.elapsed.inMilliseconds} ms, '
      '${store.eventCount} events',
    );
    expect(month, isNotEmpty);
    expect(byCategory, isNotEmpty);
    expect(projectionRows(copy), projectionRows(store));
    // Ceilings catch a missing index or a per-command full scan.
    expect(p95, lessThan(const Duration(milliseconds: 40)));
    expect(read.elapsed, lessThan(const Duration(milliseconds: 200)));
    expect(replay.elapsed, lessThan(const Duration(seconds: 60)));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
