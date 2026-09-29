import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/investment_adapter.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/investment-buy-tests')
    ..createSync(recursive: true);
  final usd = Currency('USD', 2);
  late Directory work;
  late ProbeDatabase db;
  late WorkspaceId workspace;
  late Account cash;

  OperationId operation() => OperationId(PublicId.generate());

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
    );
    cash = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic funding cash',
      kind: AccountKind.bank,
      currency: usd,
      openedOn: BusinessDate(2028, 1, 1),
    );
    await FinancialWorkflows(db).createAccount(
      cash,
      Posting.opening(
        id: PublicId.generate(),
        operation: OperationKey(workspace, operation()),
        date: cash.openedOn,
        account: PostingAccount(
          id: cash.id,
          workspace: workspace,
          currency: usd,
          expectedVersion: 1,
        ),
        amount: Money.parse(usd, '100'),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    work.deleteSync(recursive: true);
  });

  InvestmentBuyPreview preview({
    OperationId? op,
    PublicId? buyId,
    PublicId? lotId,
    InvestmentBuyPreview? basedOn,
    String fee = '1',
  }) {
    final brokerId = basedOn?.broker.id ?? PublicId.generate();
    return InvestmentBuyPreview.create(
      id: buyId ?? basedOn?.id ?? PublicId.generate(),
      lotId: lotId ?? basedOn?.lot.id ?? PublicId.generate(),
      operation:
          basedOn?.operation ?? OperationKey(workspace, op ?? operation()),
      tradedOn: BusinessDate(2028, 2, 20),
      broker: BrokerIdentity(
        id: brokerId,
        workspace: workspace,
        name: 'Synthetic broker',
      ),
      account: InvestmentAccount(
        id: basedOn?.account.id ?? PublicId.generate(),
        workspace: workspace,
        brokerId: brokerId,
        fundingCashAccountId: cash.id,
        name: 'Synthetic investment account',
        expectedVersion: 1,
      ),
      instrument: InvestmentInstrument(
        id: basedOn?.instrument.id ?? PublicId.generate(),
        kind: InstrumentKind.etf,
        marketCode: 'XNYS',
        symbol: 'SYN',
        name: 'Synthetic ETF',
        tradingCurrency: usd,
      ),
      funding: FundingCashAccount(
        id: cash.id,
        workspace: workspace,
        currency: usd,
        expectedVersion: 1,
      ),
      quantity: ShareQuantity.parse('2'),
      unitPrice: ShareUnitPrice.parse(usd, '10'),
      executedGross: Money.parse(usd, '20'),
      fee: Money.parse(usd, fee),
      tax: Money.parse(usd, '0'),
    );
  }

  Posting posting(InvestmentBuyPreview buy, PublicId eventId) =>
      Posting.investmentBuy(
        id: eventId,
        operation: buy.operation,
        date: buy.tradedOn,
        account: PostingAccount(
          id: buy.funding.id,
          workspace: buy.operation.workspace,
          currency: buy.funding.currency,
          expectedVersion: buy.funding.expectedVersion,
        ),
        investmentBuyId: buy.id,
        gross: buy.gross,
        fee: buy.fee,
        tax: buy.tax,
        cashDebit: buy.cashDebit,
      );

  test(
    'generic workflow cannot credit investment sale without lot facts',
    () async {
      final sale = Posting.investmentSell(
        id: PublicId.generate(),
        operation: OperationKey(workspace, OperationId(PublicId.generate())),
        date: BusinessDate(2028, 1, 2),
        account: PostingAccount(
          id: cash.id,
          workspace: workspace,
          currency: usd,
          expectedVersion: 1,
        ),
        investmentSellId: PublicId.generate(),
        gross: Money.parse(usd, '20'),
        fee: Money.parse(usd, '1'),
        tax: Money.parse(usd, '0'),
        cashCredit: Money.parse(usd, '19'),
      );
      expect(() => FinancialWorkflows(db).post(sale), throwsUnsupportedError);
      expect(
        await db
            .customSelect("SELECT id FROM events WHERE kind='investmentSell'")
            .get(),
        isEmpty,
      );
    },
  );

  test(
    'schema21 commits exactly one cash debit, buy, lot and receipt',
    () async {
      final buy = preview();
      final eventId = PublicId.generate();
      expect(db.schemaVersion, 21);
      final first = await commitInvestmentBuy(db, buy, posting(buy, eventId));
      final retry = await commitInvestmentBuy(db, buy, posting(buy, eventId));
      expect(first.replayed, false);
      expect(retry.replayed, true);
      expect(
        (await investmentBuys(db, workspace, buy.account.id)).single.eventId,
        eventId,
      );
      expect(
        await db.customSelect('SELECT * FROM investment_buys').get(),
        hasLength(1),
      );
      expect(
        await db.customSelect('SELECT * FROM investment_lots').get(),
        hasLength(1),
      );
      expect(
        (await db
                .customSelect(
                  'SELECT SUM(amount) AS balance FROM legs WHERE workspace=? AND account_id=?',
                  variables: [
                    Variable(workspace.toString()),
                    Variable(cash.id.value),
                  ],
                )
                .get())
            .single
            .read<int>('balance'),
        7900,
      );
      await validateInvestmentFacts(db);
    },
  );

  test('same operation with different content is rejected', () async {
    final buy = preview();
    final eventId = PublicId.generate();
    await commitInvestmentBuy(db, buy, posting(buy, eventId));
    final altered = preview(basedOn: buy, fee: '2');
    await expectLater(
      commitInvestmentBuy(db, altered, posting(altered, eventId)),
      throwsA(isA<OperationConflict>()),
    );
    expect(
      await db.customSelect('SELECT * FROM investment_buys').get(),
      hasLength(1),
    );
  });

  test('checkpoint failure rolls back event and lot together', () async {
    final buy = preview();
    final eventId = PublicId.generate();
    await expectLater(
      commitInvestmentBuy(
        db,
        buy,
        posting(buy, eventId),
        checkpoint: (stage) {
          if (stage == 'investmentLot') throw StateError('synthetic failure');
        },
      ),
      throwsStateError,
    );
    expect(
      await db.customSelect('SELECT * FROM investment_buys').get(),
      isEmpty,
    );
    expect(
      await db.customSelect('SELECT * FROM investment_lots').get(),
      isEmpty,
    );
    expect(
      await db
          .customSelect("SELECT * FROM events WHERE kind='investmentBuy'")
          .get(),
      isEmpty,
    );
  });
}
