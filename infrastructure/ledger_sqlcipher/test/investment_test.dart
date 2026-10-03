import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

final usd = Currency.of('USD');
final opened = BusinessDate(2026, 9, 1);

Money cents(int units) => Money(usd, BigInt.from(units));

Matcher fails(FailureKind kind, String diagnostic) =>
    throwsA(AppFailure(kind, diagnostic));

final settlement = BusinessDate(2026, 10, 5);

void main() {
  late Directory directory;
  late File file;
  late StorageKey key;
  late SqlCipherStore store;
  late LedgerStore ledger;
  late Bookkeeping<SqlBookkeeping> books;
  late InvestmentBook<SqlBookkeeping> invest;
  late PublicId bank;
  late PublicId brokerage;
  late PublicId apple;
  final workspace = WorkspaceId(PublicId.generate());

  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));

  void open() {
    store = SqlCipherStore.open(file, key, modules: [ledgerSchema]);
    ledger = LedgerStore(store);
    books = Bookkeeping(ledger);
    invest = InvestmentBook(books);
  }

  Account account(PublicId id) =>
      ledger.accounts(workspace).singleWhere((a) => a.id == id);

  TradeTarget target() => TradeTarget(
    accountId: brokerage,
    instrumentId: apple,
    funding: AccountRef(bank, account(bank).rulesVersion),
  );

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('ledger-invest-');
    file = File('${directory.path}/ledger.db');
    key = StorageKey.random();
    open();
    bank = PublicId.generate();
    await books.openAccount(
      OpenAccount(
        operation: op(),
        accountId: bank,
        name: '美元帳戶',
        kind: AccountKind.bank,
        currency: usd,
        openedOn: opened,
        openingBalance: cents(1000000),
        openingPostingId: PublicId.generate(),
      ),
    );
    final broker = PublicId.generate();
    await invest.registerBroker(
      RegisterBroker(operation: op(), brokerId: broker, name: '複委託'),
    );
    brokerage = PublicId.generate();
    await invest.openAccount(
      OpenInvestmentAccount(
        operation: op(),
        accountId: brokerage,
        brokerId: broker,
        fundingAccountId: bank,
        name: '美股',
      ),
    );
    apple = PublicId.generate();
    await invest.registerInstrument(
      RegisterInstrument(
        operation: op(),
        instrumentId: apple,
        kind: InstrumentKind.stock,
        marketCode: 'NASDAQ',
        symbol: 'AAPL',
        name: 'Apple',
        currency: usd,
      ),
    );
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<PublicId> buy(
    String quantity,
    String price,
    int gross, {
    int fee = 0,
    OperationKey? operation,
    BusinessDate? on,
    BusinessDate? settles,
  }) async {
    final outcome = await invest.buy(
      BuyInvestment(
        operation: operation ?? op(),
        buyId: PublicId.generate(),
        lotId: PublicId.generate(),
        postingId: PublicId.generate(),
        target: target(),
        tradedOn: on ?? BusinessDate(2026, 10, 1),
        quantity: quantity,
        unitPrice: price,
        gross: cents(gross),
        fee: cents(fee),
        tax: cents(0),
        settlesOn: settles,
      ),
    );
    return outcome.value;
  }

  Future<PublicId> sell(String quantity, String price, int gross) async {
    final outcome = await invest.sell(
      SellInvestment(
        operation: op(),
        sellId: PublicId.generate(),
        postingId: PublicId.generate(),
        target: target(),
        tradedOn: BusinessDate(2026, 10, 20),
        costMethod: InvestmentCostMethod.fifo,
        quantity: quantity,
        unitPrice: price,
        gross: cents(gross),
        fee: cents(100),
        tax: cents(0),
      ),
    );
    return outcome.value;
  }

  test('a buy debits cash, opens a lot and is not spending', () async {
    await buy('10', '150.25', 150250, fee: 100);
    expect(ledger.balance(account(bank)), cents(1000000 - 150350));
    final lots = ledger.holdings(brokerage, apple);
    expect(lots.single.remainingQuantity.toString(), '10');
    expect(lots.single.remainingCost, cents(150350));
    expect(ledger.monthly(workspace, '2026-10'), isEmpty);
  });

  test('a FIFO sell credits net cash and replays into lots', () async {
    await buy('10', '150', 150000);
    await buy('5', '160', 80000, on: BusinessDate(2026, 10, 5));
    await sell('12', '170', 204000);
    expect(
      ledger.balance(account(bank)),
      cents(1000000 - 150000 - 80000 + 203900),
    );
    final lot = ledger.holdings(brokerage, apple).single;
    expect(lot.remainingQuantity.toString(), '3');
    expect(lot.remainingCost, cents(48000));
    expect(lot.expectedVersion, 2);

    store.close();
    open();
    final replayed = ledger.holdings(brokerage, apple).single;
    expect(replayed.remainingCost, cents(48000));
    await expectLater(
      sell('4', '170', 68000),
      fails(FailureKind.rejected, 'investment.oversell'),
    );
  });

  test('a dividend credits the settlement account', () async {
    await buy('10', '150', 150000);
    await invest.dividend(
      RecordDividend(
        operation: op(),
        dividendId: PublicId.generate(),
        postingId: PublicId.generate(),
        target: target(),
        paidOn: BusinessDate(2026, 11, 15),
        gross: cents(1000),
        withholdingTax: cents(300),
        fee: cents(0),
        net: cents(700),
      ),
    );
    expect(ledger.balance(account(bank)), cents(1000000 - 150000 + 700));
    expect(ledger.monthly(workspace, '2026-11'), isEmpty);
  });

  test('investment screens list accounts, trades and income', () async {
    await buy('10', '150', 150000);
    await buy('5', '160', 80000, on: BusinessDate(2026, 10, 5));
    await sell('12', '170', 204000);
    await invest.dividend(
      RecordDividend(
        operation: op(),
        dividendId: PublicId.generate(),
        postingId: PublicId.generate(),
        target: target(),
        paidOn: BusinessDate(2026, 11, 15),
        gross: cents(1000),
        withholdingTax: cents(300),
        fee: cents(0),
        net: cents(700),
      ),
    );
    final accounts = ledger.investmentAccounts(workspace);
    expect([for (final account in accounts) account.name], ['美股']);
    expect(ledger.instrument(apple)!.symbol, 'AAPL');
    expect(ledger.positions(brokerage), [apple]);
    final history = ledger.tradeHistory(brokerage, instrumentId: apple);
    final kinds = [for (final trade in history) trade.kind];
    expect(kinds, ['dividend', 'sell', 'buy', 'buy']);
    expect(history.last.cash, cents(-150000));
    // 203900 net less the cost of 10 + 2 shares (150000 + 32000).
    expect(history[1].realized, cents(21900));
    final october = ledger.investmentIncome(
      workspace,
      from: BusinessDate(2026, 10, 1),
      through: BusinessDate(2026, 10, 31),
    )['USD']!;
    expect(october.realized, cents(21900));
    expect(october.dividends, cents(0));
    final year = ledger.investmentIncome(
      workspace,
      from: BusinessDate(2026, 1, 1),
      through: BusinessDate(2026, 12, 31),
    )['USD']!;
    expect(year.dividends, cents(700));
  });

  test('cash settles later; the lot dates from the trade', () async {
    final posting = await buy('10', '150', 150000, settles: settlement);
    final cash = ledger.postings(bank).singleWhere((p) => p.id == posting);
    expect(cash.date, settlement);
    final lot = ledger.holdings(brokerage, apple).single;
    expect(lot.acquiredOn, BusinessDate(2026, 10, 1));
    await expectLater(
      buy('1', '150', 15000, settles: BusinessDate(2026, 9, 30)),
      fails(FailureKind.rejected, 'investment.settlement'),
    );
  });

  test('only a bank or cash account settles trades', () async {
    final wallet = PublicId.generate();
    await books.openAccount(
      OpenAccount(
        operation: op(),
        accountId: wallet,
        name: '電子錢包',
        kind: AccountKind.eWallet,
        currency: usd,
        openedOn: opened,
      ),
    );
    final broker = PublicId.generate();
    await invest.registerBroker(
      RegisterBroker(operation: op(), brokerId: broker, name: '另一家'),
    );
    await expectLater(
      invest.openAccount(
        OpenInvestmentAccount(
          operation: op(),
          accountId: PublicId.generate(),
          brokerId: broker,
          fundingAccountId: wallet,
          name: '錢包投資',
        ),
      ),
      fails(FailureKind.rejected, 'investment.funding'),
    );
  });

  test('trade postings cannot be reversed directly', () async {
    final posting = await buy('1', '100', 10000);
    await expectLater(
      books.reversePosting(
        ReversePosting(
          operation: op(),
          reversalId: PublicId.generate(),
          originalId: posting,
          date: BusinessDate(2026, 10, 2),
        ),
      ),
      fails(FailureKind.rejected, 'posting.owned-elsewhere'),
    );
  });

  test('quotes, funding and retries are checked', () async {
    await expectLater(
      buy('3', '10.01', 3000),
      fails(FailureKind.rejected, 'investment.grossMismatch'),
    );
    final other = PublicId.generate();
    await books.openAccount(
      OpenAccount(
        operation: op(),
        accountId: other,
        name: '其他',
        kind: AccountKind.bank,
        currency: usd,
        openedOn: opened,
      ),
    );
    await expectLater(
      invest.buy(
        BuyInvestment(
          operation: op(),
          buyId: PublicId.generate(),
          lotId: PublicId.generate(),
          postingId: PublicId.generate(),
          target: TradeTarget(
            accountId: brokerage,
            instrumentId: apple,
            funding: AccountRef(other, 1),
          ),
          tradedOn: BusinessDate(2026, 10, 1),
          quantity: '1',
          unitPrice: '1',
          gross: cents(100),
          fee: cents(0),
          tax: cents(0),
        ),
      ),
      fails(FailureKind.rejected, 'investment.funding'),
    );
    await expectLater(
      sell('1', '1', 100),
      fails(FailureKind.rejected, 'investment.no-holdings'),
    );
    await expectLater(
      invest.registerInstrument(
        RegisterInstrument(
          operation: op(),
          instrumentId: PublicId.generate(),
          kind: InstrumentKind.stock,
          marketCode: 'NASDAQ',
          symbol: 'AAPL',
          name: 'Apple again',
          currency: usd,
        ),
      ),
      fails(FailureKind.conflict, 'investment.exists'),
    );
  });

  test('a split multiplies shares, keeps cost and replays', () async {
    await buy('10', '150', 150000);
    final changed = await invest.split(
      SplitInvestment(
        operation: op(),
        splitId: PublicId.generate(),
        accountId: brokerage,
        instrumentId: apple,
        effectiveOn: BusinessDate(2026, 10, 10),
        newShares: 4,
        oldShares: 1,
      ),
    );
    expect(changed.value, 1);
    final lot = ledger.holdings(brokerage, apple).single;
    expect(lot.remainingQuantity.toString(), '40');
    expect(lot.remainingCost, cents(150000));
    await sell('40', '40', 160000);
    expect(ledger.holdings(brokerage, apple), isEmpty);
  });

  test('a mistaken trade is voided and the holding replayed', () async {
    Future<void> buyAs(PublicId id, String quantity, int gross) async {
      await invest.buy(
        BuyInvestment(
          operation: op(),
          buyId: id,
          lotId: PublicId.generate(),
          postingId: PublicId.generate(),
          target: target(),
          tradedOn: BusinessDate(2026, 10, 1),
          quantity: quantity,
          unitPrice: '100',
          gross: cents(gross),
          fee: cents(0),
          tax: cents(0),
        ),
      );
    }

    Future<CommandOutcome<PublicId>> voidTrade(PublicId id) => invest.voidTrade(
      VoidInvestmentTrade(
        operation: op(),
        accountId: brokerage,
        instrumentId: apple,
        tradeId: id,
        reversalId: PublicId.generate(),
      ),
    );

    final first = PublicId.generate();
    final second = PublicId.generate();
    await buyAs(first, '10', 100000);
    await buyAs(second, '5', 50000);
    final dividend = PublicId.generate();
    await invest.dividend(
      RecordDividend(
        operation: op(),
        dividendId: dividend,
        postingId: PublicId.generate(),
        target: target(),
        paidOn: BusinessDate(2026, 11, 15),
        gross: cents(1000),
        withholdingTax: cents(0),
        fee: cents(0),
        net: cents(1000),
      ),
    );

    // The older buy has a later buy after it; dividends never block.
    await expectLater(
      voidTrade(first),
      fails(FailureKind.rejected, 'investment.trade-in-use'),
    );
    await voidTrade(second);
    await voidTrade(dividend);
    final lot = ledger.holdings(brokerage, apple).single;
    expect(lot.remainingQuantity.toString(), '10');
    expect(ledger.balance(account(bank)), cents(1000000 - 100000));
    await expectLater(
      voidTrade(second),
      fails(FailureKind.notFound, 'investment.not-found'),
    );
    await voidTrade(first);
    expect(ledger.holdings(brokerage, apple), isEmpty);
    expect(ledger.balance(account(bank)), cents(1000000));
  });

  test('a holding keeps the cost method of its first sell', () async {
    await buy('10', '150', 150000);
    await sell('3', '160', 48000);
    await expectLater(
      invest.sell(
        SellInvestment(
          operation: op(),
          sellId: PublicId.generate(),
          postingId: PublicId.generate(),
          target: target(),
          tradedOn: BusinessDate(2026, 10, 21),
          costMethod: InvestmentCostMethod.averageCost,
          quantity: '1',
          unitPrice: '160',
          gross: cents(16000),
          fee: cents(0),
          tax: cents(0),
        ),
      ),
      fails(FailureKind.rejected, 'investment.cost-method'),
    );
  });

  test('brokers, accounts and instruments can be renamed', () async {
    final prepared = target();
    await invest.rename(
      RenameInvestmentRecord(
        operation: op(),
        type: InvestmentRecordType.instrument,
        id: apple,
        name: 'Apple Inc.',
      ),
    );
    await invest.rename(
      RenameInvestmentRecord(
        operation: op(),
        type: InvestmentRecordType.account,
        id: brokerage,
        name: '美股帳戶',
      ),
    );
    await expectLater(
      invest.rename(
        RenameInvestmentRecord(
          operation: op(),
          type: InvestmentRecordType.broker,
          id: PublicId.generate(),
          name: 'x',
        ),
      ),
      fails(FailureKind.notFound, 'investment.not-found'),
    );
    // A trade prepared before the renames still goes through.
    await invest.buy(
      BuyInvestment(
        operation: op(),
        buyId: PublicId.generate(),
        lotId: PublicId.generate(),
        postingId: PublicId.generate(),
        target: prepared,
        tradedOn: BusinessDate(2026, 10, 1),
        quantity: '1',
        unitPrice: '100',
        gross: cents(10000),
        fee: cents(0),
        tax: cents(0),
      ),
    );
    store.close();
    open();
    expect(ledger.holdings(brokerage, apple), hasLength(1));
  });

  test('trades stay in date order around sells', () async {
    await buy('10', '150', 150000);
    await buy('5', '160', 80000, on: BusinessDate(2026, 10, 30));
    // On the 20th only the first lot was held.
    await expectLater(
      sell('12', '170', 204000),
      fails(FailureKind.rejected, 'investment.oversell'),
    );
    await sell('3', '160', 48000);
    await expectLater(
      buy('1', '150', 15000, on: BusinessDate(2026, 10, 10)),
      fails(FailureKind.rejected, 'investment.backdated'),
    );
  });
}
