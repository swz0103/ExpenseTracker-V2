import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:reports/reports.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

final twd = Currency.iso('TWD');
final usd = Currency.iso('USD');
final day = BusinessDate(2026, 10, 3);

Money ntd(int units) => Money(twd, BigInt.from(units));

void main() {
  late Directory directory;
  final workspace = WorkspaceId(PublicId.generate());

  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));

  setUp(() {
    directory = Directory.systemTemp.createTempSync('ledger-replay-');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  SqlCipherStore open(String name) => SqlCipherStore.open(
    File('${directory.path}/$name.db'),
    StorageKey.random(),
    modules: [ledgerSchema],
  );

  /// Exercises every event kind the ledger writes.
  Future<void> fill(LedgerStore ledger) async {
    final books = Bookkeeping(ledger);
    final cards = CardBook(books);
    final invest = InvestmentBook(books);
    Account account(PublicId id) =>
        ledger.accounts(workspace).singleWhere((a) => a.id == id);
    AccountRef ref(PublicId id) => AccountRef(id, account(id).version);
    Future<PublicId> open(String name, AccountKind kind, Currency c) async {
      final id = PublicId.generate();
      await books.openAccount(
        OpenAccount(
          operation: op(),
          accountId: id,
          name: name,
          kind: kind,
          currency: c,
          openedOn: day,
          openingBalance: Money(c, BigInt.from(500000)),
          openingPostingId: PublicId.generate(),
        ),
      );
      return id;
    }

    final cash = await open('現金', AccountKind.cash, twd);
    final bank = await open('銀行', AccountKind.bank, twd);
    final dollars = await open('美元', AccountKind.bank, usd);
    final card = await open('卡', AccountKind.creditCard, twd);
    final food = PublicId.generate();
    final trip = PublicId.generate();
    final shop = PublicId.generate();
    await books.changeCatalog(
      ChangeCatalog(
        operation: op(),
        catalog: CatalogType.category,
        change: CreateEntry(food, '餐飲', kind: CategoryKind.expense),
      ),
    );
    await books.changeCatalog(
      ChangeCatalog(
        operation: op(),
        catalog: CatalogType.tag,
        change: CreateEntry(trip, '旅行'),
      ),
    );
    await books.changeCatalog(
      ChangeCatalog(
        operation: op(),
        catalog: CatalogType.merchant,
        change: CreateEntry(shop, '全聯'),
      ),
    );
    final lunch = await books.recordCashFlow(
      RecordCashFlow(
        operation: op(),
        postingId: PublicId.generate(),
        flow: CashFlow.expense,
        account: ref(cash),
        date: day,
        amount: ntd(800),
        allocations: [CategoryShare(food, 1, ntd(800))],
        tags: [TagSelection(trip, 1)],
        merchant: MerchantSelection(shop, 1),
      ),
    );
    await books.setNote(
      SetNote(
        operation: op(),
        postingId: lunch.value,
        expectedRevision: 0,
        text: '和同事',
      ),
    );
    await books.recordRefund(
      RecordRefund(
        operation: op(),
        postingId: PublicId.generate(),
        originalId: lunch.value,
        account: ref(cash),
        date: day,
        amount: ntd(300),
        allocations: [CategoryShare(food, 1, ntd(300))],
      ),
    );
    final transfer = await books.recordTransfer(
      RecordTransfer(
        operation: op(),
        postingId: PublicId.generate(),
        source: ref(bank),
        destination: ref(cash),
        date: day,
        principal: ntd(1000),
        fee: ntd(15),
      ),
    );
    await books.reversePosting(
      ReversePosting(
        operation: op(),
        reversalId: PublicId.generate(),
        originalId: transfer.value,
        date: day,
      ),
    );
    await books.renameAccount(
      RenameAccount(
        operation: op(),
        accountId: cash,
        expectedVersion: 1,
        name: '錢包',
      ),
    );
    await cards.setTerms(
      SetCardTerms(
        operation: op(),
        cardId: card,
        expectedVersion: 0,
        closingDay: 25,
        dueDay: 10,
      ),
    );
    final charge = PublicId.generate();
    await cards.authorize(
      AuthorizeCardCharge(
        operation: op(),
        chargeId: charge,
        cardId: card,
        authorizedOn: day,
        amount: ntd(3000),
      ),
    );
    await cards.post(
      PostCardCharge(
        operation: op(),
        chargeId: charge,
        postingId: PublicId.generate(),
        card: ref(card),
        postedOn: day,
        settledAmount: ntd(3000),
        fee: ntd(0),
      ),
    );
    final held = PublicId.generate();
    await cards.authorize(
      AuthorizeCardCharge(
        operation: op(),
        chargeId: held,
        cardId: card,
        authorizedOn: day,
        amount: ntd(99),
      ),
    );
    await cards.release(
      ReleaseAuthorization(operation: op(), chargeId: held, cardId: card),
    );
    await cards.planInstallments(
      PlanInstallments(
        operation: op(),
        chargeId: charge,
        count: 3,
        fixedFee: ntd(0),
      ),
    );
    await cards.pay(
      PayCard(
        operation: op(),
        paymentId: PublicId.generate(),
        postingId: PublicId.generate(),
        source: ref(bank),
        card: ref(card),
        statementClose: BusinessDate(2026, 10, 25),
        postedOn: BusinessDate(2026, 11, 5),
        amount: ntd(1000),
      ),
    );
    final planning = PlanningBook(books);
    await planning.setBudget(
      SetBudget(
        operation: op(),
        budgetId: PublicId.generate(),
        expectedVersion: 0,
        month: ReportMonth(2026, 10),
        limit: ntd(9000),
        categoryId: food,
      ),
    );
    final rent = PublicId.generate();
    await planning.saveRecurring(
      SaveRecurring(
        operation: op(),
        templateId: rent,
        expectedVersion: 0,
        accountId: bank,
        label: '房租',
        amount: ntd(-12000),
        firstDate: day,
        unit: RecurrenceUnit.month,
        every: 1,
      ),
    );
    await planning.confirm(
      ConfirmRecurring(
        operation: op(),
        postingId: PublicId.generate(),
        templateId: rent,
        expectedTemplateVersion: 1,
        dueDate: day,
        account: ref(bank),
      ),
    );
    final broker = PublicId.generate();
    final brokerage = PublicId.generate();
    final apple = PublicId.generate();
    await invest.registerBroker(
      RegisterBroker(operation: op(), brokerId: broker, name: '複委託'),
    );
    await invest.openAccount(
      OpenInvestmentAccount(
        operation: op(),
        accountId: brokerage,
        brokerId: broker,
        fundingAccountId: dollars,
        name: '美股',
      ),
    );
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
    TradeTarget target() => TradeTarget(
      accountId: brokerage,
      instrumentId: apple,
      funding: ref(dollars),
    );
    Money cents(int units) => Money(usd, BigInt.from(units));
    await invest.buy(
      BuyInvestment(
        operation: op(),
        buyId: PublicId.generate(),
        lotId: PublicId.generate(),
        postingId: PublicId.generate(),
        target: target(),
        tradedOn: day,
        quantity: '4',
        unitPrice: '100',
        gross: cents(40000),
        fee: cents(100),
        tax: cents(0),
      ),
    );
    await invest.split(
      SplitInvestment(
        operation: op(),
        splitId: PublicId.generate(),
        accountId: brokerage,
        instrumentId: apple,
        effectiveOn: day,
        newShares: 2,
        oldShares: 1,
      ),
    );
    await invest.sell(
      SellInvestment(
        operation: op(),
        sellId: PublicId.generate(),
        postingId: PublicId.generate(),
        target: target(),
        tradedOn: day,
        costMethod: InvestmentCostMethod.averageCost,
        quantity: '1',
        unitPrice: '60',
        gross: cents(6000),
        fee: cents(100),
        tax: cents(0),
      ),
    );
    await invest.dividend(
      RecordDividend(
        operation: op(),
        dividendId: PublicId.generate(),
        postingId: PublicId.generate(),
        target: target(),
        paidOn: day,
        gross: cents(500),
        withholdingTax: cents(150),
        fee: cents(0),
        net: cents(350),
      ),
    );
  }

  test('replaying the journal rebuilds every projection exactly', () async {
    final source = open('source');
    final target = open('target');
    addTearDown(source.close);
    addTearDown(target.close);
    await fill(LedgerStore(source));

    final copied = await LedgerReplay.copy(
      from: source,
      to: LedgerStore(target),
      batch: 7,
    );
    expect(copied, source.eventCount);
    expect(target.eventCount, source.eventCount);
    expect(target.operationCount, source.operationCount);
    expect(projectionRows(target), projectionRows(source));
    expect(
      target.journal(limit: 1000).map((e) => '${e.seq}/${e.id}/${e.kind}'),
      source.journal(limit: 1000).map((e) => '${e.seq}/${e.id}/${e.kind}'),
    );
    expect(target.integrityCheck(), 'ok');
  });

  test('an event the replayer does not know stops the replay', () async {
    final source = open('source');
    final target = open('target');
    addTearDown(source.close);
    addTearDown(target.close);
    await source.write((transaction) async {
      transaction.append(
        id: PublicId.generate(),
        workspace: workspace,
        kind: 'mystery.changed',
        payload: '{}',
      );
    });
    await expectLater(
      LedgerReplay.copy(from: source, to: LedgerStore(target)),
      throwsA(
        isA<ReplayException>()
            .having((e) => e.kind, 'kind', 'mystery.changed')
            .having((e) => e.seq, 'seq', 1),
      ),
    );
    expect(target.eventCount, 0);
  });

  test('a payload that breaks a domain rule stops the replay', () async {
    final source = open('source');
    final target = open('target');
    addTearDown(source.close);
    addTearDown(target.close);
    await source.write((transaction) async {
      transaction.append(
        id: PublicId.generate(),
        workspace: workspace,
        kind: 'account.opened',
        payload: '{"version":1,"name":""}',
      );
    });
    await expectLater(
      LedgerReplay.copy(from: source, to: LedgerStore(target)),
      throwsA(
        isA<ReplayException>().having((e) => e.kind, 'kind', 'account.opened'),
      ),
    );
  });
}
