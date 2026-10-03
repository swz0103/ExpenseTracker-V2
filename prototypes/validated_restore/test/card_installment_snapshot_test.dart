import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/card_installments_adapter.dart';
import 'package:modular_persistence_probe/card_statements_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/card-installment-snapshot-tests')
    ..createSync(recursive: true);
  final codec = SnapshotCodec(
    generationAware: true,
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
    creditCardsAware: true,
    cardStatementsAware: true,
    cardAuthorizationsAware: true,
    installmentsAware: true,
  );
  late Directory work;
  late ProbeDatabase source;
  late AllocationFixture fixture;
  late Account card;

  ProbeDatabase database(File file, StorageBinding binding) => ProbeDatabase(
    file,
    storageBinding: binding,
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

  OperationId operation() => OperationId(PublicId.generate());

  setUp(() async {
    work = root.createTempSync('case-');
    source = database(File('${work.path}/source.db'), allocationBinding());
    fixture = AllocationFixture(source);
    await fixture.initialize();
    card = Account.open(
      id: PublicId.generate(),
      workspace: fixture.ws,
      name: 'Synthetic card',
      kind: AccountKind.creditCard,
      currency: fixture.currency,
      openedOn: BusinessDate(2026, 1, 1),
    );
    await FinancialWorkflows(source).createAccount(
      card,
      Posting.opening(
        id: PublicId.generate(),
        operation: fixture.operation(),
        date: card.openedOn,
        account: PostingAccount(
          id: card.id,
          workspace: fixture.ws,
          currency: card.currency,
          expectedVersion: 1,
        ),
        amount: Money(card.currency, BigInt.zero),
      ),
      cardTerms: CreditCardTerms(
        workspace: fixture.ws,
        cardId: card.id,
        currency: card.currency,
        closingDay: 28,
        dueDay: 15,
      ),
    );
  });

  tearDown(() async {
    await source.close();
    work.deleteSync(recursive: true);
  });

  Future<PublicId> postedPurchase() async {
    final purchase = Posting.expense(
      id: PublicId.generate(),
      operation: fixture.operation(),
      date: BusinessDate(2026, 9, 27),
      account: PostingAccount(
        id: card.id,
        workspace: fixture.ws,
        currency: card.currency,
        expectedVersion: 1,
      ),
      amount: fixture.money('101.02'),
    );
    await source.transaction(() async {
      await FinancialWorkflows(source).post(purchase);
      await registerPostedCardCharge(source, fixture.ws, purchase.id, card.id);
    });
    return purchase.id;
  }

  Future<void> addPlan() async {
    final purchase = await postedPurchase();
    await createCardInstallmentPlan(
      source,
      CardInstallmentSchedule(
        purchaseEventId: purchase,
        workspace: fixture.ws,
        cardId: card.id,
        principal: fixture.money('100.01'),
        fixedFee: fixture.money('1.01'),
        firstScheduledClose: BusinessDate(2026, 9, 28),
        closingDay: 28,
        count: 3,
      ),
      operation(),
    );
  }

  test('schema 20 plans round trip with their posted purchases', () async {
    await addPlan();
    final bytes = await codec.capture(source);
    final snapshot = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(snapshot['version'], 19);
    expect(snapshot['schema'], 20);
    expect((snapshot['tables'] as Map)['card_installment_plans'], hasLength(1));

    final binding = allocationBinding();
    final targetFile = File('${work.path}/restored.db');
    await codec.stage(
      bytes,
      targetFile,
      openDatabase: (file) => database(file, binding),
    );
    final target = database(targetFile, binding);
    try {
      expect(await codec.capture(target), bytes);
      final facts = await cardInstallmentPlans(target, fixture.ws, card.id);
      expect(facts, hasLength(1));
      expect(
        facts.single.plan.installments.last.projectedCharge.majorText,
        '33.66',
      );
    } finally {
      await target.close();
    }
  });

  test('schemas 18 and 19 upgrade with empty installment authority', () async {
    final current = await codec.capture(source);
    for (final version in [17, 18]) {
      final old = jsonDecode(utf8.decode(current)) as Map<String, dynamic>;
      old['version'] = version;
      old['schema'] = version + 1;
      (old['modules'] as Map<String, dynamic>).remove('card_installments');
      (old['tables'] as Map<String, dynamic>).remove('card_installment_plans');
      if (version == 17) {
        (old['modules'] as Map<String, dynamic>).remove('card_authorizations');
        (old['tables'] as Map<String, dynamic>)
          ..remove('card_authorizations')
          ..remove('card_authorization_resolutions');
      }
      final legacy = utf8.encode(jsonEncode(old));
      final canonical = jsonDecode(
        utf8.decode(codec.canonicalize(legacy)),
      ) as Map<String, dynamic>;
      expect(canonical['schema'], 20);
      expect((canonical['tables'] as Map)['card_installment_plans'], isEmpty);

      final binding = allocationBinding();
      final file = File('${work.path}/upgraded-$version.db');
      await codec.stage(
        legacy,
        file,
        openDatabase: (file) => database(file, binding),
      );
      final target = database(file, binding);
      try {
        expect(
          await cardInstallmentPlans(target, fixture.ws, card.id),
          isEmpty,
        );
        expect(await codec.capture(target), codec.canonicalize(legacy));
      } finally {
        await target.close();
      }
    }
  });

  test('malformed and omitted plans are rejected before restore', () async {
    await addPlan();
    final bytes = await codec.capture(source);
    final malformed = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    ((malformed['tables'] as Map)['card_installment_plans'] as List)
            .single['payload'] =
        '{}';
    await expectLater(
      codec.stage(
        utf8.encode(jsonEncode(malformed)),
        File('${work.path}/malformed.db'),
        openDatabase: (file) => database(file, allocationBinding()),
      ),
      throwsA(isA<InvalidSnapshot>()),
    );

    final wrongAmount = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final planRow =
        ((wrongAmount['tables'] as Map)['card_installment_plans'] as List)
                .single
            as Map<String, dynamic>;
    final payload =
        jsonDecode(planRow['payload'] as String) as Map<String, dynamic>;
    payload['principalMinor'] = '10000';
    planRow['payload'] = jsonEncode(payload);
    await expectLater(
      codec.stage(
        utf8.encode(jsonEncode(wrongAmount)),
        File('${work.path}/wrong-amount.db'),
        openDatabase: (file) => database(file, allocationBinding()),
      ),
      throwsA(isA<InvalidSnapshot>()),
    );

    final omitted = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    (omitted['tables'] as Map).remove('card_installment_plans');
    expect(
      () => codec.canonicalize(utf8.encode(jsonEncode(omitted))),
      throwsA(isA<InvalidSnapshot>()),
    );
    final unknown = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    (unknown['tables'] as Map)['future_installment_facts'] = [];
    expect(
      () => codec.canonicalize(utf8.encode(jsonEncode(unknown))),
      throwsA(isA<InvalidSnapshot>()),
    );

    await source.customStatement(
      "UPDATE card_installment_plans SET payload='{}'",
    );
    await expectLater(codec.capture(source), throwsA(isA<InvalidSnapshot>()));
  });

  test('schema 20 is opt in', () async {
    expect(() => SnapshotCodec(installmentsAware: true), throwsArgumentError);
    await addPlan();
    final oldCodec = SnapshotCodec(
      generationAware: true,
      correctionsAware: true,
      tombstonesAware: true,
      budgetsAware: true,
      recurringAware: true,
      creditCardsAware: true,
      cardStatementsAware: true,
      cardAuthorizationsAware: true,
    );
    await expectLater(
      oldCodec.capture(source),
      throwsA(isA<InvalidSnapshot>()),
    );
  });
}
