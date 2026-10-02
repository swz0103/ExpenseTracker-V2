import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/adapters.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/investment_adapter.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/investment-sale-tests')
    ..createSync(recursive: true);
  final usd = Currency('USD', 2);
  late Directory work;
  late ProbeDatabase db;
  late WorkspaceId workspace;
  late Account cash;
  late InvestmentBuyPreview buy;

  OperationKey operation() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
  Money money(String input) => Money.parse(usd, input);
  PostingAccount cashPosting() => PostingAccount(
    id: cash.id,
    workspace: workspace,
    currency: usd,
    expectedVersion: cash.version,
  );
  Posting salePosting(InvestmentSellPreview preview, PublicId eventId) =>
      Posting.investmentSell(
        id: eventId,
        operation: preview.operation,
        date: preview.tradedOn,
        account: cashPosting(),
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
        account: cashPosting(),
        amount: money('1000'),
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
        expectedVersion: 1,
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
        account: cashPosting(),
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
    await work.delete(recursive: true);
  });

  Future<InvestmentSellPreview> sale({
    PublicId? id,
    OperationKey? key,
    BusinessDate? tradedOn,
    InvestmentCostMethod method = InvestmentCostMethod.fifo,
  }) async => InvestmentSellPreview.create(
    id: id ?? PublicId.generate(),
    operation: key ?? operation(),
    tradedOn: tradedOn ?? BusinessDate(2028, 2, 21),
    broker: buy.broker,
    account: buy.account,
    instrument: buy.instrument,
    funding: FundingCashAccount(
      id: cash.id,
      workspace: workspace,
      currency: usd,
      expectedVersion: cash.version,
    ),
    costMethod: method,
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

  test('sale credits cash and disposes half the lot once', () async {
    final preview = await sale();
    final eventId = PublicId.generate();
    final first = await commitInvestmentSell(
      db,
      preview,
      salePosting(preview, eventId),
    );
    final retry = await commitInvestmentSell(
      db,
      preview,
      salePosting(preview, eventId),
    );
    expect(first.replayed, isFalse);
    expect(retry.replayed, isTrue);
    final lots = await investmentHoldingLots(
      db,
      workspace,
      buy.account.id,
      buy.instrument.id,
    );
    expect(lots, hasLength(1));
    expect(lots.single.remainingQuantity, ShareQuantity.parse('1'));
    expect(lots.single.remainingCost, money('10.50'));
    expect(lots.single.expectedVersion, 2);
    expect(
      await FinancialWorkflows(db).ledger.balance(cashPosting()),
      money('1008'),
    );
    expect(
      (await investmentSales(
        db,
        workspace,
        buy.account.id,
        buy.instrument.id,
      )).single.eventId,
      eventId,
    );
    expect((await allInvestmentSales(db, workspace)).single.eventId, eventId);
    await validateInvestmentSaleFacts(db);
  });

  test('a renamed funding account can settle and replay a sale', () async {
    cash = cash.rename(
      workspace: workspace,
      expectedVersion: cash.version,
      name: 'Renamed synthetic bank',
    );
    await AccountsAdapter(db).replace(cash);
    final preview = await sale();
    final posting = salePosting(preview, PublicId.generate());
    await commitInvestmentSell(db, preview, posting);
    await validateInvestmentSaleFacts(db);
    expect(
      await FinancialWorkflows(db).ledger.balance(cashPosting()),
      money('1008'),
    );
  });

  test('failure after allocation rolls back cash, sale and receipt', () async {
    final preview = await sale();
    final eventId = PublicId.generate();
    await expectLater(
      commitInvestmentSell(
        db,
        preview,
        salePosting(preview, eventId),
        checkpoint: (point) {
          if (point == 'investmentSellAllocation') throw StateError('cut');
        },
      ),
      throwsStateError,
    );
    expect(
      await FinancialWorkflows(db).ledger.balance(cashPosting()),
      money('979'),
    );
    expect(
      await investmentSales(db, workspace, buy.account.id, buy.instrument.id),
      isEmpty,
    );
    expect(
      (await investmentHoldingLots(
        db,
        workspace,
        buy.account.id,
        buy.instrument.id,
      )).single.remainingQuantity,
      ShareQuantity.parse('2'),
    );
    final retry = await commitInvestmentSell(
      db,
      preview,
      salePosting(preview, eventId),
    );
    expect(retry.replayed, isFalse);
  });

  test('second sale exhausts the lot; cost method cannot switch', () async {
    final first = await sale();
    await commitInvestmentSell(
      db,
      first,
      salePosting(first, PublicId.generate()),
    );
    final switched = await sale(
      tradedOn: BusinessDate(2028, 2, 22),
      method: InvestmentCostMethod.averageCost,
    );
    await expectLater(
      commitInvestmentSell(
        db,
        switched,
        salePosting(switched, PublicId.generate()),
      ),
      throwsFormatException,
    );
    final second = await sale(tradedOn: BusinessDate(2028, 2, 22));
    await commitInvestmentSell(
      db,
      second,
      salePosting(second, PublicId.generate()),
    );
    expect(
      await investmentHoldingLots(
        db,
        workspace,
        buy.account.id,
        buy.instrument.id,
      ),
      isEmpty,
    );
    expect(
      await FinancialWorkflows(db).ledger.balance(cashPosting()),
      money('1037'),
    );
  });

  test('reusing an operation with changed sale content is rejected', () async {
    final first = await sale();
    final eventId = PublicId.generate();
    await commitInvestmentSell(db, first, salePosting(first, eventId));
    final changed = await sale(id: first.id, key: first.operation);
    await expectLater(
      commitInvestmentSell(db, changed, salePosting(changed, eventId)),
      throwsA(isA<Exception>()),
    );
    expect(
      await FinancialWorkflows(db).ledger.balance(cashPosting()),
      money('1008'),
    );
  });

  test('tampered cash link is detected on the next holding read', () async {
    final preview = await sale();
    final eventId = PublicId.generate();
    await commitInvestmentSell(db, preview, salePosting(preview, eventId));
    await db.customStatement(
      'UPDATE events SET income=1 WHERE workspace=? AND id=?',
      [workspace.toString(), eventId.value],
    );
    await expectLater(
      investmentHoldingLots(db, workspace, buy.account.id, buy.instrument.id),
      throwsFormatException,
    );
    await expectLater(validateInvestmentSaleFacts(db), throwsFormatException);
  });

  test(
    'later purchase is allowed but a backdated purchase is rejected',
    () async {
      final first = await sale();
      await commitInvestmentSell(
        db,
        first,
        salePosting(first, PublicId.generate()),
      );
      Future<void> purchaseOn(BusinessDate date) async {
        final next = InvestmentBuyPreview.create(
          id: PublicId.generate(),
          lotId: PublicId.generate(),
          operation: operation(),
          tradedOn: date,
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
          next,
          Posting.investmentBuy(
            id: PublicId.generate(),
            operation: next.operation,
            date: next.tradedOn,
            account: cashPosting(),
            investmentBuyId: next.id,
            gross: next.gross,
            fee: next.fee,
            tax: next.tax,
            cashDebit: next.cashDebit,
          ),
        );
      }

      await expectLater(
        purchaseOn(BusinessDate(2028, 2, 21)),
        throwsFormatException,
      );
      expect(
        await FinancialWorkflows(db).ledger.balance(cashPosting()),
        money('1008'),
      );
      await purchaseOn(BusinessDate(2028, 2, 22));
      expect(
        await investmentHoldingLots(
          db,
          workspace,
          buy.account.id,
          buy.instrument.id,
        ),
        hasLength(2),
      );
      await validateInvestmentSaleFacts(db);
    },
  );
}
