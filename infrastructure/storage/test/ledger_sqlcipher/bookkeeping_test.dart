import 'dart:io';
import 'dart:math';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:domain/accounts.dart';
import 'package:domain/bookkeeping.dart';
import 'package:domain/categories.dart';
import 'package:domain/ledger.dart';
import 'package:storage/ledger_sqlcipher.dart';
import 'package:storage/storage_sqlcipher.dart';
import 'package:test/test.dart';

final twd = Currency.of('TWD');
final usd = Currency.of('USD');
final jpy = Currency.of('JPY');
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

  AccountRef ref(PublicId id) => AccountRef(id, account(id).rulesVersion);

  Future<PublicId> openAccount(
    String name,
    Currency currency, {
    Money? opening,
    AccountKind kind = AccountKind.bank,
  }) async {
    final id = PublicId.generate();
    await books.openAccount(
      OpenAccount(
        operation: op(),
        accountId: id,
        name: name,
        kind: kind,
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

  Future<PublicId> reverse(PublicId original) async {
    final outcome = await books.deletePosting(
      DeletePosting(
        operation: op(),
        reversalId: PublicId.generate(),
        originalId: original,
      ),
    );
    return outcome.value;
  }

  test('opening balance, income and expense update the projections', () async {
    final cash = await openAccount('現金', twd, opening: money(twd, 100000));
    await flow(CashFlow.income, cash, money(twd, 50000));
    await flow(CashFlow.expense, cash, money(twd, 12000));
    expect(ledger.balance(account(cash)), money(twd, 138000));
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
  });

  test('a received-currency fee is booked with its category', () async {
    final twdBank = await openAccount('台幣', twd, opening: money(twd, 500000));
    final usdBank = await openAccount('美元', usd);
    final fees = PublicId.generate();
    await books.changeCatalog(
      ChangeCatalog(
        operation: op(),
        catalog: CatalogType.category,
        change: CreateEntry(fees, '手續費', kind: CategoryKind.expense),
      ),
    );
    await books.recordTransfer(
      RecordTransfer(
        operation: op(),
        postingId: PublicId.generate(),
        source: ref(twdBank),
        destination: ref(usdBank),
        date: day,
        principal: money(twd, 320000),
        received: money(usd, 10000),
        fee: money(usd, 1500),
        feeAllocations: [CategoryShare(fees, 1, money(usd, 1500))],
      ),
    );
    expect(ledger.balance(account(twdBank)), money(twd, 180000));
    expect(ledger.balance(account(usdBank)), money(usd, 8500));
  });

  test('foreign entries count at their booked home value', () async {
    final twdBank = await openAccount('台幣', twd, opening: money(twd, 500000));
    final usdBank = await openAccount('美元', usd);
    await books.recordTransfer(
      RecordTransfer(
        operation: op(),
        postingId: PublicId.generate(),
        source: ref(twdBank),
        destination: ref(usdBank),
        date: day,
        principal: money(twd, 3200),
        received: money(usd, 10000),
      ),
    );
    Future<void> foreign(CashFlow flow, int cents, int? home) =>
        books.recordCashFlow(
          RecordCashFlow(
            operation: op(),
            postingId: PublicId.generate(),
            flow: flow,
            account: ref(usdBank),
            date: day,
            amount: money(usd, cents),
            homeValue: home == null ? null : money(twd, home),
          ),
        );
    await foreign(CashFlow.expense, 2500, 810);
    await foreign(CashFlow.income, 1000, 330);
    await foreign(CashFlow.expense, 100, null);
    await expectLater(
      books.recordCashFlow(
        RecordCashFlow(
          operation: op(),
          postingId: PublicId.generate(),
          flow: CashFlow.expense,
          account: ref(twdBank),
          date: day,
          amount: money(twd, 100),
          homeValue: money(twd, 100),
        ),
      ),
      fails(FailureKind.rejected, 'posting.home-value'),
    );
    expect(
      ledger.postingHomeValues(workspace).values,
      unorderedEquals([money(twd, 810), money(twd, 330)]),
    );
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

  test('a rename keeps prepared entries; a rules change does not', () async {
    final cash = await openAccount('現金', twd, opening: money(twd, 1000));
    final prepared = ref(cash);
    await books.renameAccount(
      RenameAccount(
        operation: op(),
        accountId: cash,
        expectedVersion: account(cash).version,
        name: '錢包',
      ),
    );
    await flow(CashFlow.expense, cash, money(twd, 100), account: prepared);
    expect(ledger.balance(account(cash)), money(twd, 900));

    for (final change in [
      AccountStateChange.archive,
      AccountStateChange.reactivate,
    ]) {
      await books.changeAccountState(
        ChangeAccountState(
          operation: op(),
          accountId: cash,
          expectedVersion: account(cash).version,
          change: change,
        ),
      );
    }
    final events = store.eventCount;
    await expectLater(
      flow(CashFlow.expense, cash, money(twd, 100), account: prepared),
      fails(FailureKind.conflict, 'account.versionConflict'),
    );
    expect(store.eventCount, events);
    expect(ledger.balance(account(cash)), money(twd, 900));
    expect(account(cash).name, '錢包');
  });

  test('net worth inclusion can be changed', () async {
    final cash = await openAccount('家人', twd);
    await books.setNetWorthInclusion(
      SetNetWorthInclusion(
        operation: op(),
        accountId: cash,
        expectedVersion: account(cash).version,
        included: false,
      ),
    );
    expect(account(cash).includeInNetWorth, isFalse);
    expect(account(cash).rulesVersion, 1);
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
        stale ? current.rulesVersion - 1 : current.rulesVersion,
      );
      final edit = stale ? current.version - 1 : current.version;
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
            await reverse(posted[random.nextInt(posted.length)]);
          case 6:
            await books.renameAccount(
              RenameAccount(
                operation: op(),
                accountId: target,
                expectedVersion: edit,
                name: '帳戶 $i',
              ),
            );
          default:
            await books.changeAccountState(
              ChangeAccountState(
                operation: op(),
                accountId: target,
                expectedVersion: edit,
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
      final all = ledger.workspacePostings(workspace);
      for (final id in accounts) {
        final current = account(id);
        final postings = [
          for (final posting in all)
            if (posting.legs.any((leg) => leg.account.id == id)) posting,
        ];
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
      expect(store.eventCount, greaterThan(store.operationCount));
      expect(store.integrityCheck(), 'ok');
    }

    verify();
    store.close();
    open();
    verify();
  });

  test('an advance is money owed, not spending, and repays in part', () async {
    final cash = await openAccount('現金', twd, opening: money(twd, 5000));
    final friend = await openAccount('小明', twd, kind: AccountKind.receivable);
    Future<void> move(PublicId from, PublicId to, int units) =>
        books.recordTransfer(
          RecordTransfer(
            operation: op(),
            postingId: PublicId.generate(),
            source: ref(from),
            destination: ref(to),
            date: day,
            principal: money(twd, units),
          ),
        );
    await move(cash, friend, 1200);
    await move(friend, cash, 500);
    expect(ledger.balance(account(friend)), money(twd, 700));
    expect(ledger.balance(account(cash)), money(twd, 4300));
    final expenses = [
      for (final posting in ledger.workspacePostings(workspace))
        posting.reportExpense.minorUnits,
    ];
    expect(expenses, everyElement(BigInt.zero));
  });
}
