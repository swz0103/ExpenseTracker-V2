import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/adapters.dart';
import 'package:modular_persistence_probe/card_revisions_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/card-revisions-tests')
    ..createSync(recursive: true);
  late Directory work;
  late ProbeDatabase db;
  late StorageBinding binding;
  late AllocationFixture fixture;
  late PublicId cardId;
  final when = DateTime.utc(2026, 9, 29, 4);

  CreditCardTerms terms(int version, int closingDay) => CreditCardTerms(
    workspace: fixture.ws,
    cardId: cardId,
    currency: fixture.currency,
    closingDay: closingDay,
    dueDay: 15,
    limit: Money.parse(fixture.currency, '10000'),
    version: version,
  );

  setUp(() async {
    work = root.createTempSync('case-');
    binding = allocationBinding();
    db = ProbeDatabase(
      File('${work.path}/finance.db'),
      storageBinding: binding,
      categoryAware: true,
      correctionsAware: true,
      tombstonesAware: true,
      budgetsAware: true,
      recurringAware: true,
      creditCardsAware: true,
    );
    fixture = AllocationFixture(db);
    await fixture.initialize();
    cardId = PublicId.generate();
    await AccountsAdapter(db).insert(
      Account.open(
        id: cardId,
        workspace: fixture.ws,
        name: 'Test card',
        kind: AccountKind.creditCard,
        currency: fixture.currency,
        openedOn: BusinessDate(2026, 9, 29),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    work.deleteSync(recursive: true);
  });

  test('card setup, edit and disable are versioned and idempotent', () async {
    expect(db.schemaVersion, 17);
    final create = OperationId(PublicId.generate());
    final original = await appendCardTermsRevision(
      db,
      terms(1, 30),
      create,
      when,
    );
    final retry = await appendCardTermsRevision(
      db,
      terms(1, 30),
      create,
      when.add(const Duration(days: 1)),
    );
    expect(retry.recordedAt, original.recordedAt);
    await appendCardTermsRevision(
      db,
      terms(2, 28),
      OperationId(PublicId.generate()),
      when,
    );
    expect((await currentCardTerms(db, fixture.ws)).single.closingDay, 28);
    await appendCardTermsRevision(
      db,
      terms(3, 28),
      OperationId(PublicId.generate()),
      when,
      disabled: true,
    );
    expect(await currentCardTerms(db, fixture.ws), isEmpty);
    expect((await cardTermsHistory(db, fixture.ws)).length, 3);
    await validateCardTermsRevisions(db);
    await expectLater(
      appendCardTermsRevision(
        db,
        terms(4, 28),
        OperationId(PublicId.generate()),
        when,
      ),
      throwsFormatException,
    );
  });

  test('wrong account kind and conflicting operation fail closed', () async {
    await expectLater(
      appendCardTermsRevision(
        db,
        CreditCardTerms(
          workspace: fixture.ws,
          cardId: fixture.account.id,
          currency: fixture.currency,
          closingDay: 30,
          dueDay: 15,
        ),
        OperationId(PublicId.generate()),
        when,
      ),
      throwsFormatException,
    );
    final operation = OperationId(PublicId.generate());
    await appendCardTermsRevision(db, terms(1, 30), operation, when);
    await expectLater(
      appendCardTermsRevision(db, terms(1, 29), operation, when),
      throwsFormatException,
    );
    await expectLater(
      appendCardTermsRevision(
        db,
        terms(3, 29),
        OperationId(PublicId.generate()),
        when,
      ),
      throwsFormatException,
    );
    expect((await currentCardTerms(db, fixture.ws)).single.closingDay, 30);
  });

  test('card opening and settings commit together and replay once', () async {
    final id = PublicId.generate();
    final account = Account.open(
      id: id,
      workspace: fixture.ws,
      name: 'New card',
      kind: AccountKind.creditCard,
      currency: fixture.currency,
      openedOn: BusinessDate(2026, 9, 29),
    );
    final opening = Posting.opening(
      id: PublicId.generate(),
      operation: OperationKey(fixture.ws, OperationId(PublicId.generate())),
      date: account.openedOn,
      account: PostingAccount(
        id: id,
        workspace: fixture.ws,
        currency: fixture.currency,
        expectedVersion: 1,
      ),
      amount: Money(fixture.currency, BigInt.zero),
    );
    final cardTerms = CreditCardTerms(
      workspace: fixture.ws,
      cardId: id,
      currency: fixture.currency,
      closingDay: 30,
      dueDay: 15,
    );
    final workflow = FinancialWorkflows(db);
    final created = await workflow.createAccount(
      account,
      opening,
      cardTerms: cardTerms,
    );
    expect(created.replayed, isFalse);
    expect(
      (await workflow.createAccount(
        account,
        opening,
        cardTerms: cardTerms,
      )).replayed,
      isTrue,
    );
    expect((await cardTermsHistory(db, fixture.ws)).length, 1);
    expect(() => workflow.createAccount(account, opening), throwsArgumentError);
  });
}
