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
  final root = Directory('.dart_tool/investment-dividend-tests')
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
  InvestmentDividendPreview dividend() => InvestmentDividendPreview.create(
    id: PublicId.generate(),
    operation: operation(),
    paidOn: BusinessDate(2028, 3, 15),
    broker: buy.broker,
    account: buy.account,
    instrument: buy.instrument,
    funding: FundingCashAccount(
      id: cash.id,
      workspace: workspace,
      currency: usd,
      expectedVersion: cash.version,
    ),
    gross: money('10.00'),
    withholdingTax: money('1.00'),
    fee: money('0.25'),
    reportedNet: money('8.75'),
  );
  Posting dividendPosting(
    InvestmentDividendPreview preview,
    PublicId eventId,
  ) => Posting.investmentDividend(
    id: eventId,
    operation: preview.operation,
    date: preview.paidOn,
    account: cashPosting(),
    investmentDividendId: preview.id,
    gross: preview.gross,
    withholdingTax: preview.withholdingTax,
    fee: preview.fee,
    cashCredit: preview.netCashCredit,
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
        amount: money('100.00'),
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
      executedGross: money('20.00'),
      fee: money('1.00'),
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
    work.deleteSync(recursive: true);
  });

  test(
    'schema23 credits one dividend fact, cash event and receipt once',
    () async {
      expect(db.schemaVersion, 23);
      final preview = dividend();
      final eventId = PublicId.generate();
      final first = await commitInvestmentDividend(
        db,
        preview,
        dividendPosting(preview, eventId),
      );
      final retry = await commitInvestmentDividend(
        db,
        preview,
        dividendPosting(preview, eventId),
      );
      expect(first.replayed, false);
      expect(retry.replayed, true);
      final facts = await investmentDividends(db, workspace);
      expect(facts, hasLength(1));
      expect(facts.single.preview.id, preview.id);
      expect(facts.single.eventId, eventId);
      expect(await LedgerAdapter(db).balance(cashPosting()), money('87.75'));
      final event = await db
          .customSelect(
            "SELECT income,expense,kind FROM events WHERE kind='investmentDividend'",
          )
          .getSingle();
      expect(event.read<int>('income'), 0);
      expect(event.read<int>('expense'), 0);
      expect(event.read<String>('kind'), 'investmentDividend');
      expect(
        await db.customSelect('SELECT * FROM investment_dividends').get(),
        hasLength(1),
      );
      await validateInvestmentDividendFacts(db);
    },
  );

  for (final cut in ['investmentDividendEvent', 'investmentDividend']) {
    test('cut at $cut rolls back all dividend rows, then retries', () async {
      final preview = dividend();
      final eventId = PublicId.generate();
      expect(
        () => commitInvestmentDividend(
          db,
          preview,
          dividendPosting(preview, eventId),
          checkpoint: (point) {
            if (point == cut) throw StateError('synthetic cut');
          },
        ),
        throwsStateError,
      );
      expect(await LedgerAdapter(db).balance(cashPosting()), money('79.00'));
      expect(
        await db
            .customSelect(
              "SELECT * FROM events WHERE kind='investmentDividend'",
            )
            .get(),
        isEmpty,
      );
      expect(
        await db.customSelect('SELECT * FROM investment_dividends').get(),
        isEmpty,
      );
      final recovered = await commitInvestmentDividend(
        db,
        preview,
        dividendPosting(preview, eventId),
      );
      expect(recovered.replayed, false);
      expect(await LedgerAdapter(db).balance(cashPosting()), money('87.75'));
      await validateInvestmentDividendFacts(db);
    });
  }

  test('reader rejects a changed authoritative dividend payload', () async {
    final preview = dividend();
    final eventId = PublicId.generate();
    await commitInvestmentDividend(
      db,
      preview,
      dividendPosting(preview, eventId),
    );
    await db.customStatement(
      'UPDATE investment_dividends SET payload=? WHERE workspace=? AND dividend_id=?',
      ['{}', workspace.toString(), preview.id.value],
    );
    expect(() => investmentDividends(db, workspace), throwsFormatException);
  });
}
