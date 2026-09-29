import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:ledger_generation_probe/safety_backup.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/card-installment-session-tests')
    ..createSync(recursive: true);
  final twd = Currency('TWD', 2);
  const password = 'synthetic-installment-safety-password';
  late Directory work, backups;
  late FixtureKeySlots keys;
  late LedgerStore source, target;
  late WorkspaceId workspace;
  late Account card;
  late PublicId purchaseId;

  OperationId op() => OperationId(PublicId.generate());
  OperationKey operation() => OperationKey(workspace, op());
  PostingAccount ref() => PostingAccount(
    id: card.id,
    workspace: workspace,
    currency: twd,
    expectedVersion: card.version,
  );
  LedgerStore ledger(
    String name,
    FixtureKeySlots slots, {
    required bool plans,
  }) {
    return LedgerStore(
      Directory('${work.path}/$name'),
      slots,
      catalogProtection: fixtureCatalogProtection(slots),
      correctionsAware: true,
      tombstonesAware: true,
      budgetsAware: true,
      recurringAware: true,
      creditCardsAware: true,
      cardStatementsAware: true,
      cardAuthorizationsAware: true,
      installmentsAware: plans,
    );
  }

  CardInstallmentSchedule plan({PublicId? eventId, Money? principal}) =>
      CardInstallmentSchedule(
        purchaseEventId: eventId ?? purchaseId,
        workspace: workspace,
        cardId: card.id,
        principal: principal ?? Money.parse(twd, '11'),
        fixedFee: Money.parse(twd, '1'),
        firstScheduledClose: BusinessDate(2026, 10, 28),
        closingDay: 28,
        count: 3,
      );

  setUp(() async {
    work = root.createTempSync('case-');
    backups = Directory('${work.path}/backups')..createSync();
    keys = FixtureKeySlots(Directory('${work.path}/keys'));
    workspace = WorkspaceId(PublicId.generate());
    source = ledger('store', keys, plans: false);
    await source.initialize(op());
    card = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic card',
      kind: AccountKind.creditCard,
      currency: twd,
      openedOn: BusinessDate(2026, 1, 1),
    );
    purchaseId = PublicId.generate();
    await source.withSession((session) async {
      await session.createAccount(
        card,
        Posting.opening(
          id: PublicId.generate(),
          operation: operation(),
          date: card.openedOn,
          account: ref(),
          amount: Money(twd, BigInt.zero),
        ),
        cardTerms: CreditCardTerms(
          workspace: workspace,
          cardId: card.id,
          currency: twd,
          closingDay: 28,
          dueDay: 15,
        ),
      );
      await session.postCardPurchase(
        Posting.expense(
          id: purchaseId,
          operation: operation(),
          date: BusinessDate(2026, 9, 30),
          account: ref(),
          amount: Money.parse(twd, '12'),
        ),
      );
    });
    target = ledger('store', keys, plans: true);
  });

  tearDown(() {
    final base = root.resolveSymbolicLinksSync();
    final resolved = work.resolveSymbolicLinksSync();
    if (!resolved.startsWith('$base${Platform.pathSeparator}')) {
      throw StateError('Unsafe synthetic cleanup');
    }
    work.deleteSync(recursive: true);
  });

  Future<void> upgrade(String recoveryKey) async {
    final request = await planCardInstallmentUpgrade(
      target,
      op(),
      PublicId.generate(),
    );
    await upgradeCardInstallments(
      target,
      request,
      backups,
      password: password,
      recoveryKey: recoveryKey,
    );
  }

  test('schema 19 keeps installment commands unavailable', () async {
    final snapshot = jsonDecode(utf8.decode(await source.snapshot())) as Map;
    expect(snapshot['schema'], 19);
    await source.withSession((session) async {
      await expectLater(
        session.createCardInstallmentPlan(plan(), op()),
        throwsUnsupportedError,
      );
    });
    expect(jsonDecode(utf8.decode(await source.snapshot())), snapshot);
  });

  test('19 to 20 preserves posted facts and verified safety backup', () async {
    final before = jsonDecode(utf8.decode(await source.snapshot())) as Map;
    final recoveryKey = (await source.backup(password)).recoveryKey;
    final request = await planCardInstallmentUpgrade(
      target,
      op(),
      PublicId.generate(),
    );
    final receipt = await upgradeCardInstallments(
      target,
      request,
      backups,
      password: password,
      recoveryKey: recoveryKey,
    );
    expect(receipt.target.generation, isNot(request.sourceGeneration));
    final after = jsonDecode(utf8.decode(await target.snapshot())) as Map;
    expect(after['schema'], 20);
    for (final entry in (before['tables'] as Map).entries) {
      expect((after['tables'] as Map)[entry.key], entry.value);
    }
    expect((after['tables'] as Map)['card_installment_plans'], isEmpty);
    final envelope = await File(
      '${backups.path}/${request.backupId.value}.envelope',
    ).readAsString();
    expect(
      jsonDecode(
        utf8.decode(await EnvelopeCodec().openWithPassword(envelope, password)),
      ),
      before,
    );
    expect(
      jsonDecode(
        utf8.decode(
          await EnvelopeCodec().openWithRecovery(envelope, recoveryKey),
        ),
      ),
      before,
    );
  });

  test(
    'session creates, reads and replays a plan without posting spend',
    () async {
      final recoveryKey = (await source.backup(password)).recoveryKey;
      await upgrade(recoveryKey);
      final creation = op();
      await target.withSession((session) async {
        expect(
          await session.availableCardInstallmentPurchases(workspace, card.id),
          hasLength(1),
        );
        final beforeBalance = (await session.accounts(workspace))
            .single
            .balance;
        final fact = await session.createCardInstallmentPlan(plan(), creation);
        expect(fact.plan.installments, hasLength(3));
        expect(
          (await session.cardInstallmentPlans(
            workspace,
            card.id,
          )).single.operation,
          creation,
        );
        expect(
          await session.availableCardInstallmentPurchases(workspace, card.id),
          isEmpty,
        );
        final saved = await session.snapshot();
        await session.createCardInstallmentPlan(plan(), creation);
        expect(await session.snapshot(), saved);
        expect(
          (await session.accounts(workspace)).single.balance,
          beforeBalance,
        );
        await expectLater(
          session.createCardInstallmentPlan(
            plan(principal: Money.parse(twd, '10')),
            creation,
          ),
          throwsFormatException,
        );
        await expectLater(
          session.createCardInstallmentPlan(plan(), op()),
          throwsFormatException,
        );
        await expectLater(
          session.createCardInstallmentPlan(
            plan(eventId: PublicId.generate()),
            op(),
          ),
          throwsFormatException,
        );
        expect(await session.snapshot(), saved);
      });
      final backup = await target.backup(password);
      final restoredKeys = FixtureKeySlots(
        Directory('${work.path}/restored-keys'),
      );
      final restored = ledger('restored', restoredKeys, plans: true);
      await restored.restore(
        backup.envelope,
        op(),
        recoveryKey: backup.recoveryKey,
      );
      await restored.withSession((session) async {
        expect(
          await session.cardInstallmentPlans(workspace, card.id),
          hasLength(1),
        );
      });
    },
  );

  test('interrupted stage retains schema 19', () async {
    final before = await source.snapshot();
    final recoveryKey = (await source.backup(password)).recoveryKey;
    final request = await planCardInstallmentUpgrade(
      target,
      op(),
      PublicId.generate(),
    );
    await expectLater(
      upgradeCardInstallments(
        target,
        request,
        backups,
        password: password,
        recoveryKey: recoveryKey,
        checkpoint: (point) {
          if (point.contains('table:card_installment_plans')) {
            throw StateError('synthetic staged interruption');
          }
        },
      ),
      throwsA(isA<GenerationUnavailable>()),
    );
    expect(await source.snapshot(), before);
    expect(
      (jsonDecode(utf8.decode(await source.snapshot())) as Map)['schema'],
      19,
    );
  });
}
