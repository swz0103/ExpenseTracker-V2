import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/card_installments_adapter.dart';
import 'package:modular_persistence_probe/card_statements_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/card-installment-tests')
    ..createSync(recursive: true);
  final twd = Currency('TWD', 2);
  late Directory work;
  late ProbeDatabase db;
  late WorkspaceId workspace;
  late Account card;
  late FinancialWorkflows flows;

  OperationId operation() => OperationId(PublicId.generate());
  PostingAccount ref(Account account) => PostingAccount(
    id: account.id,
    workspace: workspace,
    currency: account.currency,
    expectedVersion: account.version,
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
    );
    flows = FinancialWorkflows(db);
    card = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic card',
      kind: AccountKind.creditCard,
      currency: twd,
      openedOn: BusinessDate(2028, 1, 1),
    );
    await flows.createAccount(
      card,
      Posting.opening(
        id: PublicId.generate(),
        operation: OperationKey(workspace, operation()),
        date: card.openedOn,
        account: ref(card),
        amount: Money.parse(twd, '0'),
      ),
      cardTerms: CreditCardTerms(
        workspace: workspace,
        cardId: card.id,
        currency: twd,
        closingDay: 31,
        dueDay: 15,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    work.deleteSync(recursive: true);
  });

  Future<PublicId> postedPurchase() async {
    final purchase = Posting.expense(
      id: PublicId.generate(),
      operation: OperationKey(workspace, operation()),
      date: BusinessDate(2028, 2, 20),
      account: ref(card),
      amount: Money.parse(twd, '101.02'),
    );
    await flows.post(purchase);
    await registerPostedCardCharge(db, workspace, purchase.id, card.id);
    return purchase.id;
  }

  CardInstallmentSchedule plan(
    PublicId purchase, {
    String principal = '100.01',
  }) => CardInstallmentSchedule(
    purchaseEventId: purchase,
    workspace: workspace,
    cardId: card.id,
    principal: Money.parse(twd, principal),
    fixedFee: Money.parse(twd, '1.01'),
    firstScheduledClose: BusinessDate(2028, 2, 29),
    closingDay: 31,
    count: 3,
  );

  test(
    'schema20 saves only linked posted purchase, replays and validates',
    () async {
      expect(db.schemaVersion, 20);
      final purchase = await postedPurchase();
      final request = plan(purchase);
      final op = operation();
      await createCardInstallmentPlan(db, request, op);
      await createCardInstallmentPlan(db, request, op);
      await expectLater(
        createCardInstallmentPlan(db, plan(purchase, principal: '100.00'), op),
        throwsFormatException,
      );
      final saved = (await cardInstallmentPlans(db, workspace, card.id)).single;
      expect(saved.plan.installments.last.projectedCharge.majorText, '33.70');
      await validateCardInstallmentPlans(db);
      expect(await db.customSelect('SELECT * FROM events').get(), hasLength(2));
      await expectLater(
        createCardInstallmentPlan(db, request, operation()),
        throwsFormatException,
      );
      await expectLater(
        createCardInstallmentPlan(
          db,
          plan(purchase, principal: '100.00'),
          operation(),
        ),
        throwsFormatException,
      );
      expect(await cardInstallmentPlans(db, workspace, card.id), hasLength(1));
    },
  );

  test(
    'rejects an event that is not a registered posted card purchase',
    () async {
      await expectLater(
        createCardInstallmentPlan(db, plan(PublicId.generate()), operation()),
        throwsFormatException,
      );
      expect(await cardInstallmentPlans(db, workspace, card.id), isEmpty);
    },
  );

  test('wrong amount and card fail atomically without a plan row', () async {
    final purchase = await postedPurchase();
    await expectLater(
      createCardInstallmentPlan(
        db,
        plan(purchase, principal: '100.00'),
        operation(),
      ),
      throwsFormatException,
    );
    final wrongCard = CardInstallmentSchedule(
      purchaseEventId: purchase,
      workspace: workspace,
      cardId: PublicId.generate(),
      principal: Money.parse(twd, '100.01'),
      fixedFee: Money.parse(twd, '1.01'),
      firstScheduledClose: BusinessDate(2028, 2, 29),
      closingDay: 31,
      count: 3,
    );
    await expectLater(
      createCardInstallmentPlan(db, wrongCard, operation()),
      throwsFormatException,
    );
    expect(await cardInstallmentPlans(db, workspace, card.id), isEmpty);
  });

  test(
    'candidate list is sourced from valid posted Ledger purchases',
    () async {
      final purchase = await postedPurchase();
      final available = await availableCardInstallmentPurchases(
        db,
        workspace,
        card.id,
      );
      expect(available, hasLength(1));
      expect(available.single.purchaseEventId, purchase);
      expect(available.single.postedOn, BusinessDate(2028, 2, 20));
      expect(available.single.amount, Money.parse(twd, '101.02'));
      await createCardInstallmentPlan(db, plan(purchase), operation());
      expect(
        await availableCardInstallmentPurchases(db, workspace, card.id),
        isEmpty,
      );
    },
  );

  test(
    'candidate list excludes refunded purchases and fails on corruption',
    () async {
      final refunded = await postedPurchase();
      await flows.post(
        Posting.refund(
          id: PublicId.generate(),
          operation: OperationKey(workspace, operation()),
          date: BusinessDate(2028, 3, 5),
          account: ref(card),
          originalId: refunded,
          amount: Money.parse(twd, '10'),
        ),
      );
      expect(
        await availableCardInstallmentPurchases(db, workspace, card.id),
        isEmpty,
      );
      final damaged = await postedPurchase();
      await db.customStatement(
        'UPDATE events SET expense=expense+1 WHERE workspace=? AND id=?',
        [workspace.id.value, damaged.value],
      );
      await expectLater(
        availableCardInstallmentPurchases(db, workspace, card.id),
        throwsFormatException,
      );
    },
  );

  test('tampered plan payload fails validation before publication', () async {
    final purchase = await postedPurchase();
    await createCardInstallmentPlan(db, plan(purchase), operation());
    await db.customStatement(
      "UPDATE card_installment_plans SET payload='{}' WHERE workspace=?",
      [workspace.id.value],
    );
    await expectLater(validateCardInstallmentPlans(db), throwsFormatException);
  });

  test('tampered Ledger amount invalidates the stored plan', () async {
    final purchase = await postedPurchase();
    await createCardInstallmentPlan(db, plan(purchase), operation());
    await db.customStatement(
      'UPDATE events SET expense=expense+1 WHERE workspace=? AND id=?',
      [workspace.id.value, purchase.value],
    );
    await expectLater(validateCardInstallmentPlans(db), throwsFormatException);
  });

  test(
    'a later refund retains historical plan but blocks a new plan',
    () async {
      final purchase = await postedPurchase();
      final request = plan(purchase);
      final op = operation();
      await createCardInstallmentPlan(db, request, op);
      await flows.post(
        Posting.refund(
          id: PublicId.generate(),
          operation: OperationKey(workspace, operation()),
          date: BusinessDate(2028, 3, 5),
          account: ref(card),
          originalId: purchase,
          amount: Money.parse(twd, '10'),
        ),
      );
      await validateCardInstallmentPlans(db);
      expect(await cardInstallmentPlans(db, workspace, card.id), hasLength(1));
      await createCardInstallmentPlan(db, request, op);

      final otherPurchase = await postedPurchase();
      await flows.post(
        Posting.refund(
          id: PublicId.generate(),
          operation: OperationKey(workspace, operation()),
          date: BusinessDate(2028, 3, 5),
          account: ref(card),
          originalId: otherPurchase,
          amount: Money.parse(twd, '10'),
        ),
      );
      await expectLater(
        createCardInstallmentPlan(db, plan(otherPurchase), operation()),
        throwsFormatException,
      );
    },
  );
}
