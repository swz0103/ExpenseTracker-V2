import 'dart:io';
import 'dart:math';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

final twd = Currency.iso('TWD');
final usd = Currency.iso('USD');
final jpy = Currency.iso('JPY');
final day = BusinessDate(2026, 10, 1);

Money money(Currency currency, int units) =>
    Money(currency, BigInt.from(units));

Matcher fails(FailureKind kind, String diagnostic) =>
    throwsA(AppFailure(kind, diagnostic));

void main() {
  late Directory directory;
  late File file;
  late StorageKey key;
  late SqlCipherStore store;
  late LedgerStore ledger;
  late Bookkeeping<SqlBookkeeping> books;
  final workspace = WorkspaceId(PublicId.generate());

  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));

  void open() {
    store = SqlCipherStore.open(file, key, modules: [ledgerSchema]);
    ledger = LedgerStore(store);
    books = Bookkeeping(ledger);
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('ledger-sqlcipher-');
    file = File('${directory.path}/ledger.db');
    key = StorageKey.random();
    open();
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Account account(PublicId id) =>
      ledger.accounts(workspace).singleWhere((a) => a.id == id);

  AccountRef ref(PublicId id) => AccountRef(id, account(id).version);

  Future<PublicId> openAccount(
    String name,
    Currency currency, {
    Money? opening,
  }) async {
    final id = PublicId.generate();
    await books.openAccount(
      OpenAccount(
        operation: op(),
        accountId: id,
        name: name,
        kind: AccountKind.bank,
        currency: currency,
        openedOn: day,
        openingBalance: opening,
        openingPostingId: opening == null ? null : PublicId.generate(),
      ),
    );
    return id;
  }

  Future<PublicId> flow(
    CashFlow flow,
    PublicId accountId,
    Money amount, {
    BusinessDate? date,
    OperationKey? operation,
    PublicId? postingId,
    AccountRef? account,
  }) async {
    final outcome = await books.recordCashFlow(
      RecordCashFlow(
        operation: operation ?? op(),
        postingId: postingId ?? PublicId.generate(),
        flow: flow,
        account: account ?? ref(accountId),
        date: date ?? day,
        amount: amount,
      ),
    );
    return outcome.value;
  }

  Future<PublicId> reverse(PublicId original, {BusinessDate? date}) async {
    final outcome = await books.reversePosting(
      ReversePosting(
        operation: op(),
        reversalId: PublicId.generate(),
        originalId: original,
        date: date ?? day,
      ),
    );
    return outcome.value;
  }

  test('opening balance, income and expense update the projections', () async {
    final cash = await openAccount('現金', twd, opening: money(twd, 100000));
    await flow(CashFlow.income, cash, money(twd, 50000));
    await flow(CashFlow.expense, cash, money(twd, 12000));
    expect(ledger.balance(account(cash)), money(twd, 138000));
    final october = ledger.monthly(workspace, '2026-10')['TWD']!;
    expect(october.income, money(twd, 50000));
    expect(october.expense, money(twd, 12000));
    expect(store.eventCount, 4);
    expect(store.operationCount, 3);
  });

  test('a cross-currency transfer books both legs and the fee', () async {
    final twdBank = await openAccount('台幣', twd, opening: money(twd, 500000));
    final usdBank = await openAccount('美元', usd);
    await books.recordTransfer(
      RecordTransfer(
        operation: op(),
        postingId: PublicId.generate(),
        source: ref(twdBank),
        destination: ref(usdBank),
        date: day,
        principal: money(twd, 320000),
        received: money(usd, 10000),
        fee: money(twd, 1500),
      ),
    );
    expect(ledger.balance(account(twdBank)), money(twd, 178500));
    expect(ledger.balance(account(usdBank)), money(usd, 10000));
    final october = ledger.monthly(workspace, '2026-10')['TWD']!;
    expect(october.income, money(twd, 0));
    expect(october.expense, money(twd, 1500));
  });

  test('a reversal negates the original on its own date', () async {
    final cash = await openAccount('現金', twd);
    final income = await flow(CashFlow.income, cash, money(twd, 9900));
    await reverse(income, date: BusinessDate(2026, 11, 2));
    expect(ledger.balance(account(cash)), money(twd, 0));
    final october = ledger.monthly(workspace, '2026-10')['TWD']!;
    final november = ledger.monthly(workspace, '2026-11')['TWD']!;
    expect(october.income, money(twd, 9900));
    expect(november.income, money(twd, -9900));
    expect(ledger.postings(cash), hasLength(2));
  });

  test('a posting can be reversed only once, and never a reversal', () async {
    final cash = await openAccount('現金', twd);
    final income = await flow(CashFlow.income, cash, money(twd, 100));
    final reversal = await reverse(income);
    await expectLater(
      reverse(income),
      fails(FailureKind.conflict, 'posting.already-reversed'),
    );
    await expectLater(
      reverse(reversal),
      fails(FailureKind.rejected, 'ledger.reversalReference'),
    );
    await expectLater(
      reverse(PublicId.generate()),
      fails(FailureKind.notFound, 'posting.not-found'),
    );
  });

  test('a stale account version is a conflict and writes nothing', () async {
    final cash = await openAccount('現金', twd);
    final stale = ref(cash);
    await books.renameAccount(
      RenameAccount(
        operation: op(),
        accountId: cash,
        expectedVersion: stale.expectedVersion,
        name: '錢包',
      ),
    );
    final events = store.eventCount;
    await expectLater(
      flow(CashFlow.expense, cash, money(twd, 100), account: stale),
      fails(FailureKind.conflict, 'account.versionConflict'),
    );
    expect(store.eventCount, events);
    expect(ledger.balance(account(cash)), money(twd, 0));
    expect(account(cash).name, '錢包');
  });

  test('archived accounts refuse postings until reactivated', () async {
    final cash = await openAccount('現金', twd);
    Future<void> change(AccountStateChange change) => books.changeAccountState(
      ChangeAccountState(
        operation: op(),
        accountId: cash,
        expectedVersion: account(cash).version,
        change: change,
      ),
    );
    await change(AccountStateChange.archive);
    await expectLater(
      flow(CashFlow.income, cash, money(twd, 100)),
      fails(FailureKind.rejected, 'account.unavailable'),
    );
    await change(AccountStateChange.reactivate);
    await flow(CashFlow.income, cash, money(twd, 100));
    expect(ledger.balance(account(cash)), money(twd, 100));
    expect(account(cash).state, AccountState.active);
  });

  test('a retried command replays without posting twice', () async {
    final cash = await openAccount('現金', twd);
    final operation = op();
    final postingId = PublicId.generate();
    final version = ref(cash);
    Future<CommandOutcome<PublicId>> record(int units) => books.recordCashFlow(
      RecordCashFlow(
        operation: operation,
        postingId: postingId,
        flow: CashFlow.expense,
        account: version,
        date: day,
        amount: money(twd, units),
      ),
    );
    final first = await record(500);
    final retry = await record(500);
    expect(retry.replayed, isTrue);
    expect(retry.value, first.value);
    expect(ledger.balance(account(cash)), money(twd, -500));
    await expectLater(
      record(600),
      throwsA(const AppFailure.operationConflict()),
    );
    await expectLater(
      flow(CashFlow.expense, cash, money(twd, 1), postingId: postingId),
      fails(FailureKind.conflict, 'posting.exists'),
    );
  });

  test('wrong currency, unknown account and same-account transfer', () async {
    final cash = await openAccount('現金', twd);
    await expectLater(
      flow(CashFlow.income, cash, money(usd, 100)),
      fails(FailureKind.rejected, 'account.currencyMismatch'),
    );
    await expectLater(
      flow(
        CashFlow.income,
        cash,
        money(twd, 100),
        account: AccountRef(PublicId.generate(), 1),
      ),
      fails(FailureKind.notFound, 'account.not-found'),
    );
    await expectLater(
      books.recordTransfer(
        RecordTransfer(
          operation: op(),
          postingId: PublicId.generate(),
          source: ref(cash),
          destination: ref(cash),
          date: day,
          principal: money(twd, 100),
        ),
      ),
      fails(FailureKind.rejected, 'ledger.sameAccount'),
    );
  });

  test('projections equal a rebuild from stored postings', () async {
    final random = Random(20261003);
    final accounts = [
      await openAccount('台幣 A', twd, opening: money(twd, 1000000)),
      await openAccount('台幣 B', twd),
      await openAccount('美元', usd, opening: money(usd, 50000)),
      await openAccount('日圓', jpy),
    ];
    final posted = <PublicId>[];
    var refused = 0;
    for (var i = 0; i < 300; i++) {
      final target = accounts[random.nextInt(accounts.length)];
      final current = account(target);
      final stale = random.nextInt(10) == 0;
      final version = AccountRef(
        target,
        stale ? current.version - 1 : current.version,
      );
      final date = BusinessDate(2026, 9 + random.nextInt(3), 1 + i % 28);
      final units = 1 + random.nextInt(20000);
      try {
        switch (random.nextInt(8)) {
          case 0 || 1:
            posted.add(
              await flow(
                CashFlow.income,
                target,
                money(current.currency, units),
                date: date,
                account: version,
              ),
            );
          case 2 || 3:
            posted.add(
              await flow(
                CashFlow.expense,
                target,
                money(current.currency, units),
                date: date,
                account: version,
              ),
            );
          case 4:
            final other = accounts[random.nextInt(accounts.length)];
            final otherCurrency = account(other).currency;
            final outcome = await books.recordTransfer(
              RecordTransfer(
                operation: op(),
                postingId: PublicId.generate(),
                source: version,
                destination: ref(other),
                date: date,
                principal: money(current.currency, units),
                received: money(otherCurrency, 1 + units ~/ 3),
                fee: random.nextBool() ? money(current.currency, 15) : null,
              ),
            );
            posted.add(outcome.value);
          case 5:
            if (posted.isEmpty) continue;
            await reverse(posted[random.nextInt(posted.length)], date: date);
          case 6:
            await books.renameAccount(
              RenameAccount(
                operation: op(),
                accountId: target,
                expectedVersion: version.expectedVersion,
                name: '帳戶 $i',
              ),
            );
          default:
            await books.changeAccountState(
              ChangeAccountState(
                operation: op(),
                accountId: target,
                expectedVersion: version.expectedVersion,
                change: current.state == AccountState.active
                    ? AccountStateChange.archive
                    : AccountStateChange.reactivate,
              ),
            );
        }
      } on AppFailure {
        refused++;
      }
    }
    expect(refused, greaterThan(0));
    expect(posted.length, greaterThan(20));

    void verify() {
      final all = <PublicId, Posting>{};
      for (final id in accounts) {
        final current = account(id);
        final postings = ledger.postings(id);
        for (final posting in postings) {
          all[posting.id] = posting;
        }
        final participant = PostingAccount(
          id: id,
          workspace: workspace,
          currency: current.currency,
          expectedVersion: current.version,
        );
        expect(
          ledger.balance(current),
          rebuildBalance(participant, postings),
          reason: current.name,
        );
      }
      final expected = <String, (BigInt, BigInt)>{};
      for (final posting in all.values) {
        final income = posting.reportIncome;
        if (income.minorUnits == BigInt.zero &&
            posting.reportExpense.minorUnits == BigInt.zero) {
          continue;
        }
        final month = posting.date.toString().substring(0, 7);
        final bucket = '$month/${income.currency.code}';
        final (i, e) = expected[bucket] ?? (BigInt.zero, BigInt.zero);
        expected[bucket] = (
          i + income.minorUnits,
          e + posting.reportExpense.minorUnits,
        );
      }
      for (final entry in expected.entries) {
        final [month, code] = entry.key.split('/');
        final total = ledger.monthly(workspace, month)[code]!;
        expect(total.income.minorUnits, entry.value.$1, reason: entry.key);
        expect(total.expense.minorUnits, entry.value.$2, reason: entry.key);
      }
      expect(store.eventCount, greaterThan(store.operationCount));
      expect(store.integrityCheck(), 'ok');
    }

    verify();
    store.close();
    open();
    verify();
  });
}
