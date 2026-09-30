import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/adapters.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/investment_adapter.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/investment-split-tests')
    ..createSync(recursive: true);
  final usd = Currency('USD', 2);
  late Directory work;
  late ProbeDatabase db;
  late WorkspaceId workspace;
  late Account cash;
  late InvestmentBuyPreview buy;

  OperationKey operation() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
  PostingAccount cashRef() => PostingAccount(
    id: cash.id,
    workspace: workspace,
    currency: usd,
    expectedVersion: cash.version,
  );
  Money money(String amount) => Money.parse(usd, amount);

  Future<StockSplitPreview> split({BusinessDate? date}) async =>
      StockSplitPreview.create(
        id: PublicId.generate(),
        operation: operation(),
        effectiveOn: date ?? BusinessDate(2028, 3, 15),
        broker: buy.broker,
        account: buy.account,
        instrument: buy.instrument,
        newShares: 2,
        oldShares: 1,
        lots: await investmentHoldingLots(
          db,
          workspace,
          buy.account.id,
          buy.instrument.id,
        ),
      );

  Future<InvestmentSellPreview> sale({BusinessDate? date}) async =>
      InvestmentSellPreview.create(
        id: PublicId.generate(),
        operation: operation(),
        tradedOn: date ?? BusinessDate(2028, 3, 20),
        broker: buy.broker,
        account: buy.account,
        instrument: buy.instrument,
        funding: buy.funding,
        costMethod: InvestmentCostMethod.fifo,
        quantity: ShareQuantity.parse('1'),
        unitPrice: ShareUnitPrice.parse(usd, '30'),
        executedGross: money('30'),
        fee: money('1'),
        tax: money('0'),
        lots: await investmentHoldingLots(
          db,
          workspace,
          buy.account.id,
          buy.instrument.id,
        ),
      );

  Posting salePosting(InvestmentSellPreview preview) => Posting.investmentSell(
    id: PublicId.generate(),
    operation: preview.operation,
    date: preview.tradedOn,
    account: cashRef(),
    investmentSellId: preview.id,
    gross: preview.gross,
    fee: preview.fee,
    tax: preview.tax,
    cashCredit: preview.cashCredit,
  );

  setUp(() async {
    work = root.createTempSync('case-');
    workspace = WorkspaceId(PublicId.generate());
    db = ProbeDatabase(
      File('${work.path}/finance.db'),
      storageBinding: allocationBinding(),
      categoryAware: true,
      correctionsAware: true,
      tombstonesAware: true,
      budgetsAware: true,
      recurringAware: true,
      creditCardsAware: true,
      cardStatementsAware: true,
      cardAuthorizationsAware: true,
      installmentsAware: true,
      investmentsAware: true,
      investmentSalesAware: true,
      investmentDividendsAware: true,
      investmentSplitsAware: true,
    );
    cash = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic bank',
      kind: AccountKind.bank,
      currency: usd,
      openedOn: BusinessDate(2028, 1, 1),
    );
    await FinancialWorkflows(db).createAccount(
      cash,
      Posting.opening(
        id: PublicId.generate(),
        operation: operation(),
        date: cash.openedOn,
        account: cashRef(),
        amount: money('100'),
      ),
    );
    final broker = BrokerIdentity(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic broker',
    );
    final account = InvestmentAccount(
      id: PublicId.generate(),
      workspace: workspace,
      brokerId: broker.id,
      fundingCashAccountId: cash.id,
      name: 'Synthetic portfolio',
      expectedVersion: 1,
    );
    final instrument = InvestmentInstrument(
      id: PublicId.generate(),
      kind: InstrumentKind.etf,
      marketCode: 'XNYS',
      symbol: 'SYN',
      name: 'Synthetic ETF',
      tradingCurrency: usd,
    );
    buy = InvestmentBuyPreview.create(
      id: PublicId.generate(),
      lotId: PublicId.generate(),
      operation: operation(),
      tradedOn: BusinessDate(2028, 2, 20),
      broker: broker,
      account: account,
      instrument: instrument,
      funding: FundingCashAccount(
        id: cash.id,
        workspace: workspace,
        currency: usd,
        expectedVersion: cash.version,
      ),
      quantity: ShareQuantity.parse('2'),
      unitPrice: ShareUnitPrice.parse(usd, '10'),
      executedGross: money('20'),
      fee: money('1'),
      tax: money('0'),
    );
    await commitInvestmentBuy(
      db,
      buy,
      Posting.investmentBuy(
        id: PublicId.generate(),
        operation: buy.operation,
        date: buy.tradedOn,
        account: cashRef(),
        investmentBuyId: buy.id,
        gross: buy.gross,
        fee: buy.fee,
        tax: buy.tax,
        cashDebit: buy.cashDebit,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    work.deleteSync(recursive: true);
  });

  test(
    'split atomically doubles quantity without changing cost or cash',
    () async {
      expect(db.schemaVersion, 24);
      final preview = await split();
      expect((await commitInvestmentSplit(db, preview)).replayed, isFalse);
      expect((await commitInvestmentSplit(db, preview)).replayed, isTrue);
      final lots = await investmentHoldingLots(
        db,
        workspace,
        buy.account.id,
        buy.instrument.id,
      );
      expect(lots.single.remainingQuantity.toString(), '4');
      expect(lots.single.remainingCost, money('21'));
      expect(lots.single.expectedVersion, 2);
      expect(await LedgerAdapter(db).balance(cashRef()), money('79'));
      expect(
        (await investmentSplits(db, workspace)).single.preview.id,
        preview.id,
      );
      expect(
        await db.customSelect('SELECT * FROM investment_split_lots').get(),
        hasLength(1),
      );
      expect(await db.customSelect('SELECT * FROM events').get(), hasLength(2));
      await validateInvestmentSplitFacts(db);
    },
  );

  test(
    'one action updates every open lot with independent unchanged basis',
    () async {
      final second = InvestmentBuyPreview.create(
        id: PublicId.generate(),
        lotId: PublicId.generate(),
        operation: operation(),
        tradedOn: BusinessDate(2028, 2, 21),
        broker: buy.broker,
        account: buy.account,
        instrument: buy.instrument,
        funding: buy.funding,
        quantity: ShareQuantity.parse('1'),
        unitPrice: ShareUnitPrice.parse(usd, '10'),
        executedGross: money('10'),
        fee: money('0'),
        tax: money('0'),
      );
      await commitInvestmentBuy(
        db,
        second,
        Posting.investmentBuy(
          id: PublicId.generate(),
          operation: second.operation,
          date: second.tradedOn,
          account: cashRef(),
          investmentBuyId: second.id,
          gross: second.gross,
          fee: second.fee,
          tax: second.tax,
          cashDebit: second.cashDebit,
        ),
      );
      final preview = await split();
      expect(preview.lots, hasLength(2));
      await commitInvestmentSplit(db, preview);
      final lots = await investmentHoldingLots(
        db,
        workspace,
        buy.account.id,
        buy.instrument.id,
      );
      expect(lots.map((row) => row.remainingQuantity.toString()), ['4', '2']);
      expect(lots.map((row) => row.remainingCost.majorText), [
        '21.00',
        '10.00',
      ]);
      expect(
        (await investmentSplits(db, workspace)).single.preview.lots,
        hasLength(2),
      );
      await validateInvestmentSplitFacts(db);
    },
  );

  for (final cut in [
    'investmentSplit',
    'investmentSplitLot',
    'receipt',
    'audit',
  ]) {
    test('cut at $cut rolls back all split facts then retries', () async {
      final preview = await split();
      await expectLater(
        commitInvestmentSplit(
          db,
          preview,
          checkpoint: (point) {
            if (point == cut) throw StateError('synthetic cut');
          },
        ),
        throwsStateError,
      );
      expect(
        await db.customSelect('SELECT * FROM investment_splits').get(),
        isEmpty,
      );
      expect(
        await db.customSelect('SELECT * FROM investment_split_lots').get(),
        isEmpty,
      );
      expect(
        (await investmentHoldingLots(
          db,
          workspace,
          buy.account.id,
          buy.instrument.id,
        )).single.remainingQuantity.toString(),
        '2',
      );
      expect((await commitInvestmentSplit(db, preview)).replayed, isFalse);
      await validateInvestmentSplitFacts(db);
    });
  }

  test('changed lot and split-history backfill are rejected', () async {
    final stale = await split(date: BusinessDate(2028, 3, 17));
    final fresh = await split(date: BusinessDate(2028, 3, 16));
    await commitInvestmentSplit(db, fresh);
    await expectLater(
      commitInvestmentSplit(db, stale),
      throwsA(
        isA<StockSplitException>().having(
          (error) => error.code,
          'code',
          StockSplitError.staleLots,
        ),
      ),
    );
    expect((await investmentSplits(db, workspace)), hasLength(1));
    final backfill = await split(date: BusinessDate(2028, 3, 15));
    await expectLater(
      commitInvestmentSplit(db, backfill),
      throwsFormatException,
    );
  });

  test(
    'sale after split uses expanded quantity and preserves residual cost',
    () async {
      await commitInvestmentSplit(db, await split());
      final preview = await sale();
      await commitInvestmentSell(db, preview, salePosting(preview));
      final lot = (await investmentHoldingLots(
        db,
        workspace,
        buy.account.id,
        buy.instrument.id,
      )).single;
      expect(lot.remainingQuantity.toString(), '3');
      expect(lot.remainingCost, money('15.75'));
      expect(await LedgerAdapter(db).balance(cashRef()), money('108'));
      await validateInvestmentSplitFacts(db);
    },
  );

  test('split cannot be backdated on or before a saved sale', () async {
    final preview = await sale(date: BusinessDate(2028, 3, 15));
    await commitInvestmentSell(db, preview, salePosting(preview));
    final backfill = await split(date: BusinessDate(2028, 3, 15));
    await expectLater(
      commitInvestmentSplit(db, backfill),
      throwsFormatException,
    );
    expect(await investmentSplits(db, workspace), isEmpty);
  });

  test(
    'new purchase cannot be backdated into a saved split snapshot',
    () async {
      await commitInvestmentSplit(db, await split());
      final laterBuy = InvestmentBuyPreview.create(
        id: PublicId.generate(),
        lotId: PublicId.generate(),
        operation: operation(),
        tradedOn: BusinessDate(2028, 3, 15),
        broker: buy.broker,
        account: buy.account,
        instrument: buy.instrument,
        funding: buy.funding,
        quantity: ShareQuantity.parse('1'),
        unitPrice: ShareUnitPrice.parse(usd, '10'),
        executedGross: money('10'),
        fee: money('0'),
        tax: money('0'),
      );
      await expectLater(
        commitInvestmentBuy(
          db,
          laterBuy,
          Posting.investmentBuy(
            id: PublicId.generate(),
            operation: laterBuy.operation,
            date: laterBuy.tradedOn,
            account: cashRef(),
            investmentBuyId: laterBuy.id,
            gross: laterBuy.gross,
            fee: laterBuy.fee,
            tax: laterBuy.tax,
            cashDebit: laterBuy.cashDebit,
          ),
        ),
        throwsFormatException,
      );
      expect((await investmentBuys(db, workspace)), hasLength(1));
      await validateInvestmentSplitFacts(db);
    },
  );

  test('tampered split lot fails authority validation', () async {
    final preview = await split();
    await commitInvestmentSplit(db, preview);
    await db.customStatement(
      'UPDATE investment_split_lots SET after_quantity_units=? WHERE split_id=?',
      ['9', preview.id.value],
    );
    await expectLater(validateInvestmentSplitFacts(db), throwsFormatException);
  });
}
