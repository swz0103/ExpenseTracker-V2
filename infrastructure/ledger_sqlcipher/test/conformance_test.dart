import 'dart:io';
import 'dart:math';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:bookkeeping/memory.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

/// The in-memory store the web preview uses must behave like the
/// encrypted one: the same commands succeed or fail the same way and leave
/// the same balances and monthly totals.
void main() {
  late Directory directory;
  late SqlCipherStore store;
  late LedgerStore ledger;
  late Bookkeeping<SqlBookkeeping> sql;
  late MemoryBookkeeping memoryStore;
  late Bookkeeping<MemoryBookkeepingTransaction> memory;
  final workspace = WorkspaceId(PublicId.generate());
  final twd = Currency.of('TWD');
  final usd = Currency.of('USD');
  Money money(Currency currency, int units) =>
      Money(currency, BigInt.from(units));
  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));

  setUp(() {
    directory = Directory.systemTemp.createTempSync('ledger-conformance-');
    store = SqlCipherStore.open(
      File('${directory.path}/ledger.db'),
      StorageKey.random(),
      modules: [ledgerSchema],
    );
    ledger = LedgerStore(store);
    sql = Bookkeeping(ledger);
    memoryStore = MemoryBookkeeping();
    memory = Bookkeeping(memoryStore);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  /// Runs [action] on both stores; both must succeed or fail alike.
  Future<bool> both(
    Future<Object?> Function(Bookkeeping<BookkeepingTransaction> books) action,
  ) async {
    AppFailure? sqlFailure;
    AppFailure? memoryFailure;
    try {
      await action(sql);
    } on AppFailure catch (failure) {
      sqlFailure = failure;
    }
    try {
      await action(memory);
    } on AppFailure catch (failure) {
      memoryFailure = failure;
    }
    expect(memoryFailure, sqlFailure);
    return sqlFailure == null;
  }

  test('memory and SQLCipher bookkeeping agree', () async {
    final random = Random(20261004);
    final accounts = <PublicId>[];
    for (final (name, currency) in [('現金', twd), ('銀行', twd), ('美元', usd)]) {
      final id = PublicId.generate();
      final opening = money(currency, 500000);
      final openingId = PublicId.generate();
      await both(
        (books) => books.openAccount(
          OpenAccount(
            operation: op(),
            accountId: id,
            name: name,
            kind: AccountKind.bank,
            currency: currency,
            openedOn: BusinessDate(2026, 8, 1),
            openingBalance: opening,
            openingPostingId: openingId,
          ),
        ),
      );
      accounts.add(id);
    }
    Account account(PublicId id) =>
        ledger.accounts(workspace).singleWhere((a) => a.id == id);
    AccountRef ref(PublicId id) => AccountRef(id, account(id).rulesVersion);
    Account kept(PublicId id) =>
        memoryStore.accounts(workspace).singleWhere((a) => a.id == id);

    final expenses = <PublicId>[];
    final posted = <PublicId>[];
    var refused = 0;
    for (var i = 0; i < 200; i++) {
      final target = accounts[random.nextInt(accounts.length)];
      final currency = account(target).currency;
      final version = account(target).version;
      final from = ref(target);
      final date = BusinessDate(2026, 8 + random.nextInt(3), 1 + i % 28);
      final units = 1 + random.nextInt(20000);
      final id = PublicId.generate();
      final second = PublicId.generate();
      final bool ok;
      switch (random.nextInt(9)) {
        case 0 || 1 || 2:
          final flow = random.nextBool() ? CashFlow.income : CashFlow.expense;
          ok = await both(
            (books) => books.recordCashFlow(
              RecordCashFlow(
                operation: op(),
                postingId: id,
                flow: flow,
                account: from,
                date: date,
                amount: money(currency, units),
              ),
            ),
          );
          if (ok && flow == CashFlow.expense) expenses.add(id);
        case 3:
          final other = accounts[random.nextInt(accounts.length)];
          final otherCurrency = account(other).currency;
          final to = ref(other);
          final fee = random.nextBool() ? money(currency, 15) : null;
          ok = await both(
            (books) => books.recordTransfer(
              RecordTransfer(
                operation: op(),
                postingId: id,
                source: from,
                destination: to,
                date: date,
                principal: money(currency, units),
                received: money(otherCurrency, 1 + units ~/ 3),
                fee: fee,
              ),
            ),
          );
        case 4:
          if (posted.isEmpty) continue;
          final original = posted[random.nextInt(posted.length)];
          ok = await both(
            (books) => books.reversePosting(
              ReversePosting(
                operation: op(),
                reversalId: id,
                originalId: original,
                date: date,
              ),
            ),
          );
        case 5:
          if (expenses.isEmpty) continue;
          final original = expenses[random.nextInt(expenses.length)];
          ok = await both(
            (books) => books.recordRefund(
              RecordRefund(
                operation: op(),
                postingId: id,
                originalId: original,
                account: from,
                date: date,
                amount: money(twd, 1 + units ~/ 10),
              ),
            ),
          );
        case 6:
          if (expenses.isEmpty) continue;
          final original = expenses[random.nextInt(expenses.length)];
          ok = await both(
            (books) => books.correctCashFlow(
              CorrectCashFlow(
                operation: op(),
                replacementId: id,
                originalId: original,
                reversalId: second,
                account: from,
                date: date,
                amount: money(currency, units),
              ),
            ),
          );
          if (ok) expenses.add(id);
        case 7:
          if (posted.isEmpty) continue;
          final original = posted[random.nextInt(posted.length)];
          ok = await both(
            (books) => books.deletePosting(
              DeletePosting(
                operation: op(),
                reversalId: id,
                originalId: original,
              ),
            ),
          );
        default:
          ok = await both(
            (books) => books.renameAccount(
              RenameAccount(
                operation: op(),
                accountId: target,
                expectedVersion: version,
                name: '帳戶 $i',
              ),
            ),
          );
      }
      if (ok) {
        posted.add(id);
      } else {
        refused++;
      }
    }
    expect(refused, greaterThan(0));
    expect(posted.length, greaterThan(50));

    for (final id in accounts) {
      final stored = account(id);
      final mirror = kept(id);
      expect(mirror.version, stored.version);
      expect(mirror.name, stored.name);
      final sqlIds = {for (final p in ledger.postings(id)) p.id};
      final memoryIds = {
        for (final p in memoryStore.postings(workspace))
          if (p.legs.any((leg) => leg.account.id == id)) p.id,
      };
      final missing = [
        for (final p in memoryStore.postings(workspace))
          if (memoryIds.contains(p.id) && !sqlIds.contains(p.id)) p.kind.name,
      ];
      final extra = [
        for (final p in ledger.postings(id))
          if (!memoryIds.contains(p.id)) p.kind.name,
      ];
      final byId = {for (final p in ledger.postings(id)) p.id: p};
      final differing = <String>[];
      for (final p in memoryStore.postings(workspace)) {
        final other = byId[p.id];
        if (other == null) continue;
        String legs(Posting posting) => [
          for (final leg in posting.legs)
            '${leg.account.id.value}:${leg.amount.minorUnits}',
        ].join(',');
        if (legs(p) != legs(other)) {
          differing.add('${p.kind.name}: ${legs(p)} / ${legs(other)}');
        }
      }
      expect(differing, isEmpty, reason: 'stored differently');
      expect(missing, isEmpty, reason: 'only in memory');
      expect(extra, isEmpty, reason: 'only in SQLCipher');
      expect(
        memoryStore.balance(mirror).minorUnits,
        ledger.balance(stored).minorUnits,
      );
    }
    for (final month in ['2026-08', '2026-09', '2026-10']) {
      final stored = ledger.monthly(workspace, month);
      final copy = memoryStore.monthly(workspace, month);
      for (final code in {...stored.keys, ...copy.keys}) {
        final zero = money(Currency.of(code), 0);
        expect(
          copy[code]?.income ?? zero,
          stored[code]?.income ?? zero,
          reason: '$month $code income',
        );
        expect(
          copy[code]?.expense ?? zero,
          stored[code]?.expense ?? zero,
          reason: '$month $code expense',
        );
      }
    }
  });
}
