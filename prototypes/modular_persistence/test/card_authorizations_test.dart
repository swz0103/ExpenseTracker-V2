import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/card_authorizations_adapter.dart';
import 'package:modular_persistence_probe/card_statements_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/card-authorization-tests')
    ..createSync(recursive: true);
  final twd = Currency('TWD', 2);
  final usd = Currency('USD', 2);
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
        closingDay: 28,
        dueDay: 15,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    work.deleteSync(recursive: true);
  });

  CardCharge pending() => CardCharge.pending(
    id: PublicId.generate(),
    workspace: workspace,
    cardId: card.id,
    kind: CardChargeKind.purchase,
    authorizedOn: BusinessDate(2026, 3, 1),
    authorizedAmount: Money.parse(usd, '10'),
  );

  test('pending and cancelled facts never create Ledger events', () async {
    expect(db.schemaVersion, 19);
    final charge = pending();
    final create = operation();
    final created = await createCardAuthorization(db, charge, create);
    expect(created.state, CardAuthorizationState.pending);
    expect(created.charge.ledgerEventId, isNull);
    expect(
      (await createCardAuthorization(db, charge, create)).creationOperation,
      create,
    );
    expect(
      await db.customSelect('SELECT * FROM events').get(),
      hasLength(1), // Card opening only.
    );
    expect(
      () => createCardAuthorization(db, pending(), create),
      throwsFormatException,
    );
    expect(
      () => createCardAuthorization(db, charge, operation()),
      throwsFormatException,
    );
    final cancel = operation();
    final cancelled = await cancelCardAuthorization(
      db,
      workspace,
      charge.id,
      cancel,
    );
    expect(cancelled.state, CardAuthorizationState.cancelled);
    expect(cancelled.charge.ledgerEventId, isNull);
    expect(
      (await cancelCardAuthorization(db, workspace, charge.id, cancel)).state,
      CardAuthorizationState.cancelled,
    );
    expect(
      () => cancelCardAuthorization(db, workspace, charge.id, operation()),
      throwsFormatException,
    );
    expect(
      () => postCardAuthorization(
        db,
        workspace: workspace,
        chargeId: charge.id,
        operation: operation(),
        eventId: PublicId.generate(),
        postedOn: BusinessDate(2026, 2, 28),
        settledAmount: Money.parse(twd, '300'),
        fee: Money.parse(twd, '0'),
      ),
      throwsA(anything),
    );
    await validateCardStatementFacts(db);
  });

  test('posting binds authorization to the same Ledger transaction', () async {
    final charge = pending();
    await createCardAuthorization(db, charge, operation());
    final postOperation = operation();
    final postedOn = BusinessDate(2026, 2, 28);
    final event = Posting.expense(
      id: PublicId.generate(),
      operation: OperationKey(workspace, postOperation),
      date: postedOn,
      account: ref(card),
      amount: Money.parse(twd, '305'),
    );
    await db.transaction(() async {
      await flows.post(event);
      await registerPostedCardCharge(db, workspace, event.id, card.id);
      await postCardAuthorization(
        db,
        workspace: workspace,
        chargeId: charge.id,
        operation: postOperation,
        eventId: event.id,
        postedOn: postedOn,
        settledAmount: Money.parse(twd, '300'),
        fee: Money.parse(twd, '5'),
      );
    });
    final retry = await postCardAuthorization(
      db,
      workspace: workspace,
      chargeId: charge.id,
      operation: postOperation,
      eventId: event.id,
      postedOn: postedOn,
      settledAmount: Money.parse(twd, '300'),
      fee: Money.parse(twd, '5'),
    );
    expect(retry.state, CardAuthorizationState.posted);
    expect(retry.charge.id, charge.id);
    expect(retry.charge.authorizedAmount, Money.parse(usd, '10'));
    expect(retry.charge.settledAmount, Money.parse(twd, '300'));
    expect(retry.charge.fee, Money.parse(twd, '5'));
    expect(retry.charge.postedOn, postedOn);
    expect(retry.charge.ledgerEventId, event.id);
    expect(
      () => postCardAuthorization(
        db,
        workspace: workspace,
        chargeId: charge.id,
        operation: postOperation,
        eventId: event.id,
        postedOn: postedOn,
        settledAmount: Money.parse(twd, '301'),
        fee: Money.parse(twd, '4'),
      ),
      throwsA(anything),
    );
    await validateCardStatementFacts(db);
    await db.customStatement(
      'UPDATE card_authorization_resolutions SET fee_minor=4 '
      'WHERE workspace=? AND charge_id=?',
      [workspace.id.value, charge.id.value],
    );
    expect(() => validateCardStatementFacts(db), throwsFormatException);
  });

  test(
    'failed link rolls back Ledger and leaves authorization pending',
    () async {
      final charge = pending();
      await createCardAuthorization(db, charge, operation());
      final event = Posting.expense(
        id: PublicId.generate(),
        operation: OperationKey(workspace, operation()),
        date: BusinessDate(2026, 2, 28),
        account: ref(card),
        amount: Money.parse(twd, '305'),
      );
      await expectLater(
        db.transaction(() async {
          await flows.post(event);
          await registerPostedCardCharge(db, workspace, event.id, card.id);
          await postCardAuthorization(
            db,
            workspace: workspace,
            chargeId: charge.id,
            operation: event.operation.operation,
            eventId: event.id,
            postedOn: event.date,
            settledAmount: Money.parse(twd, '300'),
            fee: Money.parse(twd, '4'),
          );
        }),
        throwsFormatException,
      );
      expect(
        (await cardAuthorizations(db, workspace)).single.state,
        CardAuthorizationState.pending,
      );
      expect(
        await db
            .customSelect(
              'SELECT * FROM events WHERE workspace=? AND id=?',
              variables: [
                Variable(workspace.id.value),
                Variable(event.id.value),
              ],
            )
            .get(),
        isEmpty,
      );
      await validateCardStatementFacts(db);
    },
  );
}
