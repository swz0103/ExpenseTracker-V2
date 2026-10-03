import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

final twd = Currency.of('TWD');
final opened = BusinessDate(2026, 9, 1);
final purchaseDay = BusinessDate(2026, 10, 3);
final close = BusinessDate(2026, 10, 25);

Money ntd(int units) => Money(twd, BigInt.from(units));

Matcher fails(FailureKind kind, String diagnostic) =>
    throwsA(AppFailure(kind, diagnostic));

void main() {
  late Directory directory;
  late SqlCipherStore store;
  late LedgerStore ledger;
  late Bookkeeping<SqlBookkeeping> books;
  late CardBook<SqlBookkeeping> cards;
  late PublicId bank;
  late PublicId card;
  final workspace = WorkspaceId(PublicId.generate());

  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));

  Future<PublicId> open(String name, AccountKind kind, {Money? opening}) async {
    final id = PublicId.generate();
    await books.openAccount(
      OpenAccount(
        operation: op(),
        accountId: id,
        name: name,
        kind: kind,
        currency: twd,
        openedOn: opened,
        openingBalance: opening,
        openingPostingId: opening == null ? null : PublicId.generate(),
      ),
    );
    return id;
  }

  Account account(PublicId id) =>
      ledger.accounts(workspace).singleWhere((a) => a.id == id);

  AccountRef ref(PublicId id) => AccountRef(id, account(id).rulesVersion);

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('ledger-cards-');
    store = SqlCipherStore.open(
      File('${directory.path}/ledger.db'),
      StorageKey.random(),
      modules: [ledgerSchema],
    );
    ledger = LedgerStore(store);
    books = Bookkeeping(ledger);
    cards = CardBook(books);
    bank = await open('銀行', AccountKind.bank, opening: ntd(100000));
    card = await open('信用卡', AccountKind.creditCard);
    await cards.setTerms(
      SetCardTerms(
        operation: op(),
        cardId: card,
        expectedVersion: 0,
        closingDay: 25,
        dueDay: 10,
      ),
    );
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<PublicId> post({
    PublicId? chargeId,
    int settled = 1200,
    int fee = 0,
    List<CategoryShare> shares = const [],
  }) async {
    final outcome = await cards.post(
      PostCardCharge(
        operation: op(),
        chargeId: chargeId ?? PublicId.generate(),
        postingId: PublicId.generate(),
        card: ref(card),
        postedOn: purchaseDay,
        settledAmount: ntd(settled),
        fee: ntd(fee),
        allocations: shares,
      ),
    );
    return outcome.value;
  }

  test('terms are versioned and only cards have them', () async {
    expect(ledger.cardTerms(card)!.closingDay, 25);
    await expectLater(
      cards.setTerms(
        SetCardTerms(
          operation: op(),
          cardId: card,
          expectedVersion: 0,
          closingDay: 5,
          dueDay: 20,
        ),
      ),
      fails(FailureKind.conflict, 'card.versionConflict'),
    );
    await expectLater(
      cards.setTerms(
        SetCardTerms(
          operation: op(),
          cardId: bank,
          expectedVersion: 0,
          closingDay: 5,
          dueDay: 20,
        ),
      ),
      fails(FailureKind.rejected, 'card.not-a-card'),
    );
  });

  test('an authorization stays pending until posted', () async {
    final chargeId = PublicId.generate();
    await cards.authorize(
      AuthorizeCardCharge(
        operation: op(),
        chargeId: chargeId,
        cardId: card,
        authorizedOn: purchaseDay,
        amount: ntd(1000),
      ),
    );
    expect(ledger.statement(card, close).pendingCount, 1);
    expect(ledger.balance(account(card)), ntd(0));

    await post(chargeId: chargeId, settled: 1050, fee: 30);
    final statement = ledger.statement(card, close);
    expect(statement.pendingCount, 0);
    expect(statement.purchases, ntd(1050));
    expect(statement.fees, ntd(30));
    expect(statement.remainingDue, ntd(1080));
    expect(ledger.balance(account(card)), ntd(-1080));
    expect(ledger.monthly(workspace, '2026-10')['TWD']!.expense, ntd(1080));

    await expectLater(
      post(chargeId: chargeId, settled: 1050, fee: 30),
      fails(FailureKind.rejected, 'card.alreadyPosted'),
    );
  });

  test('card screens list holds, statement lines and credit', () async {
    await cards.setTerms(
      SetCardTerms(
        operation: op(),
        cardId: card,
        expectedVersion: 1,
        closingDay: 25,
        dueDay: 10,
        limit: ntd(50000),
      ),
    );
    final held = PublicId.generate();
    await cards.authorize(
      AuthorizeCardCharge(
        operation: op(),
        chargeId: held,
        cardId: card,
        authorizedOn: purchaseDay,
        amount: ntd(800),
      ),
    );
    await post(settled: 1200, fee: 30);
    final pending = ledger.pendingCharges(card);
    expect([for (final charge in pending) charge.id], [held]);
    final items = ledger.statementItems(card, close);
    expect([for (final c in items.charges) c.settledAmount], [ntd(1200)]);
    expect(items.installments, isEmpty);
    expect(items.payments, isEmpty);
    // 50000 less 1230 posted and 800 still held.
    expect(ledger.availableCredit(card), ntd(47970));
  });

  test('past statements keep their dates; the issuer can move one', () async {
    await post(settled: 1000);
    await cards.setTerms(
      SetCardTerms(
        operation: op(),
        cardId: card,
        expectedVersion: 1,
        closingDay: 5,
        dueDay: 20,
        effectiveFrom: BusinessDate(2026, 11, 5),
      ),
    );
    expect(ledger.statement(card, purchaseDay).cycle.closesOn, close);
    final next = ledger.statement(card, BusinessDate(2026, 10, 30)).cycle;
    expect(next.closesOn, BusinessDate(2026, 11, 5));
    final actualClose = BusinessDate(2026, 10, 26);
    await cards.overrideCycle(
      OverrideCardCycle(
        operation: op(),
        cardId: card,
        expectedVersion: 2,
        scheduledClose: close,
        closesOn: actualClose,
        dueOn: BusinessDate(2026, 11, 11),
      ),
    );
    await cards.pay(
      PayCard(
        operation: op(),
        paymentId: PublicId.generate(),
        postingId: PublicId.generate(),
        source: ref(bank),
        card: ref(card),
        statementClose: actualClose,
        postedOn: BusinessDate(2026, 11, 8),
        amount: ntd(1000),
      ),
    );
    expect(ledger.statement(card, purchaseDay).remainingDue, ntd(0));
  });

  test('paying the bill is a transfer, not new spending', () async {
    await post(settled: 5000);
    await cards.pay(
      PayCard(
        operation: op(),
        paymentId: PublicId.generate(),
        postingId: PublicId.generate(),
        source: ref(bank),
        card: ref(card),
        statementClose: close,
        postedOn: BusinessDate(2026, 11, 8),
        amount: ntd(3000),
      ),
    );
    final statement = ledger.statement(card, close);
    expect(statement.payments, ntd(3000));
    expect(statement.remainingDue, ntd(2000));
    expect(ledger.balance(account(bank)), ntd(97000));
    expect(ledger.balance(account(card)), ntd(-2000));
    expect(ledger.monthly(workspace, '2026-10')['TWD']!.expense, ntd(5000));
    expect(ledger.monthly(workspace, '2026-11'), isEmpty);

    await expectLater(
      cards.pay(
        PayCard(
          operation: op(),
          paymentId: PublicId.generate(),
          postingId: PublicId.generate(),
          source: ref(bank),
          card: ref(card),
          statementClose: BusinessDate(2026, 10, 24),
          postedOn: BusinessDate(2026, 11, 8),
          amount: ntd(1),
        ),
      ),
      fails(FailureKind.rejected, 'card.statement-close'),
    );
  });

  test('a card refund lowers the bill and the spending', () async {
    final purchase = PublicId.generate();
    await post(chargeId: purchase, settled: 3000, fee: 30);
    Future<CommandOutcome<PublicId>> refund(int units) => cards.refund(
      RefundCardCharge(
        operation: op(),
        refundChargeId: PublicId.generate(),
        postingId: PublicId.generate(),
        originalChargeId: purchase,
        card: ref(card),
        postedOn: BusinessDate(2026, 10, 10),
        amount: ntd(units),
      ),
    );
    await refund(1000);
    final statement = ledger.statement(card, close);
    expect(statement.purchases, ntd(3000));
    expect(statement.refunds, ntd(1000));
    expect(statement.remainingDue, ntd(2030));
    expect(ledger.balance(account(card)), ntd(-2030));
    expect(ledger.monthly(workspace, '2026-10')['TWD']!.expense, ntd(2030));
    // The fee is never refunded by the merchant.
    await expectLater(
      refund(2001),
      fails(FailureKind.rejected, 'ledger.refundLimit'),
    );
    await refund(2000);
    expect(ledger.statement(card, close).remainingDue, ntd(30));
  });

  test('a mistaken charge or payment is voided on the card', () async {
    final wrong = PublicId.generate();
    final posting = await post(chargeId: wrong, settled: 800);
    await post(settled: 500);
    Future<CommandOutcome<PublicId>> voidCharge(PublicId id) =>
        cards.voidCharge(
          VoidCardCharge(
            operation: op(),
            chargeId: id,
            reversalId: PublicId.generate(),
          ),
        );
    await voidCharge(wrong);
    expect(ledger.statement(card, close).purchases, ntd(500));
    expect(ledger.balance(account(card)), ntd(-500));
    expect(ledger.monthly(workspace, '2026-10')['TWD']!.expense, ntd(500));
    await expectLater(
      voidCharge(wrong),
      fails(FailureKind.conflict, 'card.voided'),
    );
    await expectLater(
      books.reversePosting(
        ReversePosting(
          operation: op(),
          reversalId: PublicId.generate(),
          originalId: posting,
          date: purchaseDay,
        ),
      ),
      fails(FailureKind.conflict, 'posting.already-reversed'),
    );

    final payment = PublicId.generate();
    await cards.pay(
      PayCard(
        operation: op(),
        paymentId: payment,
        postingId: PublicId.generate(),
        source: ref(bank),
        card: ref(card),
        statementClose: close,
        postedOn: BusinessDate(2026, 11, 8),
        amount: ntd(5000),
      ),
    );
    expect(ledger.statement(card, close).credit, ntd(4500));
    await cards.voidPayment(
      VoidCardPayment(
        operation: op(),
        paymentId: payment,
        reversalId: PublicId.generate(),
      ),
    );
    final statement = ledger.statement(card, close);
    expect(statement.payments, ntd(0));
    expect(statement.remainingDue, ntd(500));
    expect(ledger.balance(account(bank)), ntd(100000));
  });

  test('a refunded purchase cannot be voided', () async {
    final purchase = PublicId.generate();
    await post(chargeId: purchase, settled: 900);
    await cards.refund(
      RefundCardCharge(
        operation: op(),
        refundChargeId: PublicId.generate(),
        postingId: PublicId.generate(),
        originalChargeId: purchase,
        card: ref(card),
        postedOn: purchaseDay,
        amount: ntd(100),
      ),
    );
    await expectLater(
      cards.voidCharge(
        VoidCardCharge(
          operation: op(),
          chargeId: purchase,
          reversalId: PublicId.generate(),
        ),
      ),
      fails(FailureKind.rejected, 'posting.has-refunds'),
    );
  });

  test('a card takes postings only from card commands', () async {
    await expectLater(
      books.recordCashFlow(
        RecordCashFlow(
          operation: op(),
          postingId: PublicId.generate(),
          flow: CashFlow.expense,
          account: ref(card),
          date: purchaseDay,
          amount: ntd(100),
        ),
      ),
      fails(FailureKind.rejected, 'card.use-card-commands'),
    );
    await expectLater(
      books.recordTransfer(
        RecordTransfer(
          operation: op(),
          postingId: PublicId.generate(),
          source: ref(bank),
          destination: ref(card),
          date: purchaseDay,
          principal: ntd(100),
        ),
      ),
      fails(FailureKind.rejected, 'card.use-card-commands'),
    );
    expect(ledger.balance(account(card)), ntd(0));
  });

  test('card postings are corrected on the card, not reversed', () async {
    final posting = await post();
    await expectLater(
      books.reversePosting(
        ReversePosting(
          operation: op(),
          reversalId: PublicId.generate(),
          originalId: posting,
          date: purchaseDay,
        ),
      ),
      fails(FailureKind.rejected, 'posting.owned-elsewhere'),
    );
  });

  test('installments forecast from the purchase statement onward', () async {
    final chargeId = PublicId.generate();
    final posting = await post(chargeId: chargeId, settled: 10001);
    final count = await cards.planInstallments(
      PlanInstallments(
        operation: op(),
        chargeId: chargeId,
        count: 3,
        fixedFee: ntd(0),
      ),
    );
    expect(count.value, 3);
    final plan = ledger.installments(posting);
    expect(plan.map((i) => i.scheduledClose), [
      close,
      BusinessDate(2026, 11, 25),
      BusinessDate(2026, 12, 25),
    ]);
    expect(plan.map((i) => i.principal), [ntd(3335), ntd(3333), ntd(3333)]);
    // Each statement bills one installment; the card still owes the rest.
    final october = ledger.statement(card, purchaseDay);
    expect(october.purchases, ntd(0));
    expect(october.installmentsDue, ntd(3335));
    expect(october.remainingDue, ntd(3335));
    final november = ledger.statement(card, BusinessDate(2026, 11, 10));
    expect(november.carriedOver, ntd(3335));
    expect(november.installmentsDue, ntd(3333));
    expect(ledger.balance(account(card)), ntd(-10001));
    await expectLater(
      cards.planInstallments(
        PlanInstallments(
          operation: op(),
          chargeId: chargeId,
          count: 6,
          fixedFee: ntd(0),
        ),
      ),
      fails(FailureKind.conflict, 'card.plan-exists'),
    );
  });

  test('only posted charges split; purchases keep categories', () async {
    final pending = PublicId.generate();
    await cards.authorize(
      AuthorizeCardCharge(
        operation: op(),
        chargeId: pending,
        cardId: card,
        authorizedOn: purchaseDay,
        amount: ntd(800),
      ),
    );
    await expectLater(
      cards.planInstallments(
        PlanInstallments(
          operation: op(),
          chargeId: pending,
          count: 3,
          fixedFee: ntd(0),
        ),
      ),
      fails(FailureKind.rejected, 'card.not-posted'),
    );
    final food = PublicId.generate();
    await books.changeCatalog(
      ChangeCatalog(
        operation: op(),
        catalog: CatalogType.category,
        change: CreateEntry(food, '餐飲', kind: CategoryKind.expense),
      ),
    );
    final share = CategoryShare(food, 1, ntd(720));
    await post(settled: 700, fee: 20, shares: [share]);
    final totals = ledger.categoryTotals(workspace, '2026-10');
    expect(totals[(food, 'TWD')]!.expense, ntd(720));
  });

  test('a released authorization leaves the statement', () async {
    final chargeId = PublicId.generate();
    await cards.authorize(
      AuthorizeCardCharge(
        operation: op(),
        chargeId: chargeId,
        cardId: card,
        authorizedOn: purchaseDay,
        amount: ntd(500),
      ),
    );
    expect(ledger.statement(card, close).pendingCount, 1);
    await cards.release(
      ReleaseAuthorization(operation: op(), chargeId: chargeId, cardId: card),
    );
    expect(ledger.statement(card, close).pendingCount, 0);
    await expectLater(
      post(chargeId: chargeId),
      fails(FailureKind.rejected, 'card.released'),
    );
  });
}
