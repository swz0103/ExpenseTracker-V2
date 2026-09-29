import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/card_statements_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/card-statement-tests')
    ..createSync(recursive: true);
  final twd = Currency('TWD', 2);
  late Directory work;
  late ProbeDatabase db;
  late WorkspaceId workspace;
  late Account card, bank;
  late FinancialWorkflows flows;

  OperationKey operation() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
  PostingAccount ref(Account account) => PostingAccount(
    id: account.id,
    workspace: workspace,
    currency: account.currency,
    expectedVersion: account.version,
  );
  Posting opening(Account account, String amount) => Posting.opening(
    id: PublicId.generate(),
    operation: operation(),
    date: account.openedOn,
    account: ref(account),
    amount: Money.parse(account.currency, amount),
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
    );
    flows = FinancialWorkflows(db);
    card = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic card',
      kind: AccountKind.creditCard,
      currency: twd,
      openedOn: BusinessDate(2026, 1, 1),
    );
    bank = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic bank',
      kind: AccountKind.bank,
      currency: twd,
      openedOn: BusinessDate(2026, 1, 1),
    );
    await flows.createAccount(
      card,
      opening(card, '0'),
      cardTerms: CreditCardTerms(
        workspace: workspace,
        cardId: card.id,
        currency: twd,
        closingDay: 28,
        dueDay: 15,
      ),
    );
    await flows.createAccount(bank, opening(bank, '1000'));
  });

  tearDown(() async {
    await db.close();
    work.deleteSync(recursive: true);
  });

  test(
    'schema 18 records purchase, actual bill and partial allocation',
    () async {
      expect(db.schemaVersion, 18);
      final purchase = Posting.expense(
        id: PublicId.generate(),
        operation: operation(),
        date: BusinessDate(2026, 2, 20),
        account: ref(card),
        amount: Money.parse(twd, '100'),
      );
      await flows.post(purchase);
      await registerPostedCardCharge(db, workspace, purchase.id, card.id);
      await registerPostedCardCharge(db, workspace, purchase.id, card.id);
      final payment = Posting.transfer(
        id: PublicId.generate(),
        operation: operation(),
        date: BusinessDate(2026, 3, 5),
        source: ref(bank),
        destination: ref(card),
        principal: Money.parse(twd, '30'),
      );
      await flows.post(payment);
      await registerCardPayment(db, workspace, payment.id, card.id);
      expect(
        (await unallocatedCardPayments(
          db,
          workspace,
          card.id,
        )).single.unallocated.majorText,
        '30.00',
      );
      final statementId = PublicId.generate();
      final cycle = CardCycle(
        startsAfter: BusinessDate(2026, 1, 28),
        closesOn: BusinessDate(2026, 2, 28),
        dueOn: BusinessDate(2026, 3, 15),
      );
      await appendCardStatementRevision(
        db,
        workspace: workspace,
        statementId: statementId,
        cardId: card.id,
        revision: 1,
        cycle: cycle,
        billed: Money.parse(twd, '100'),
        operation: OperationId(PublicId.generate()),
      );
      final allocationOperation = OperationId(PublicId.generate());
      await allocateCardPayment(
        db,
        workspace: workspace,
        paymentEventId: payment.id,
        statementId: statementId,
        statementRevision: 1,
        amount: Money.parse(twd, '20'),
        operation: allocationOperation,
      );
      await allocateCardPayment(
        db,
        workspace: workspace,
        paymentEventId: payment.id,
        statementId: statementId,
        statementRevision: 1,
        amount: Money.parse(twd, '20'),
        operation: allocationOperation,
      );
      final bills = await confirmedCardStatements(db, workspace, card.id);
      expect(bills.single.billed.majorText, '100.00');
      expect(bills.single.paid.majorText, '20.00');
      expect(bills.single.remainingDue.majorText, '80.00');
      expect(
        (await unallocatedCardPayments(
          db,
          workspace,
          card.id,
        )).single.unallocated.majorText,
        '10.00',
      );
      await validateCardStatementFacts(db);
      await expectLater(
        allocateCardPayment(
          db,
          workspace: workspace,
          paymentEventId: payment.id,
          statementId: statementId,
          statementRevision: 1,
          amount: Money.parse(twd, '11'),
          operation: OperationId(PublicId.generate()),
        ),
        throwsFormatException,
      );
      expect(
        (await confirmedCardStatements(
          db,
          workspace,
          card.id,
        )).single.remainingDue.majorText,
        '80.00',
      );
      await allocateCardPayment(
        db,
        workspace: workspace,
        paymentEventId: payment.id,
        statementId: statementId,
        statementRevision: 1,
        amount: Money.parse(twd, '10'),
        operation: OperationId(PublicId.generate()),
      );
      expect(
        (await confirmedCardStatements(
          db,
          workspace,
          card.id,
        )).single.remainingDue.majorText,
        '70.00',
      );
      expect(await unallocatedCardPayments(db, workspace, card.id), isEmpty);
    },
  );

  test('unlinked card event is rejected by whole-ledger validation', () async {
    final purchase = Posting.expense(
      id: PublicId.generate(),
      operation: operation(),
      date: BusinessDate(2026, 2, 20),
      account: ref(card),
      amount: Money.parse(twd, '10'),
    );
    await flows.post(purchase);
    await expectLater(validateCardStatementFacts(db), throwsFormatException);
    await registerPostedCardCharge(db, workspace, purchase.id, card.id);
    await validateCardStatementFacts(db);
  });
}
