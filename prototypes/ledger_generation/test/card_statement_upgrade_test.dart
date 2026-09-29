import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:ledger_generation_probe/safety_backup.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:test/test.dart';

const password = 'synthetic-card-statement-upgrade-password';

void main() {
  final root = Directory('.dart_tool/card-statement-upgrade-tests')
    ..createSync(recursive: true);
  final twd = Currency('TWD', 2);
  late Directory work, backups;
  late FixtureKeySlots keys;
  late LedgerStore source, target;
  late WorkspaceId workspace;
  late Account card, bank;
  late Posting charge, payment;
  late String recoveryKey;
  late String legacyEnvelope;

  OperationId op() => OperationId(PublicId.generate());
  OperationKey operation() => OperationKey(workspace, op());
  PostingAccount ref(Account account) => PostingAccount(
    id: account.id,
    workspace: workspace,
    currency: account.currency,
    expectedVersion: account.version,
  );
  LedgerStore ledger(
    String name,
    FixtureKeySlots slots, {
    required bool facts,
  }) => LedgerStore(
    Directory('${work.path}/$name'),
    slots,
    catalogProtection: fixtureCatalogProtection(slots),
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
    creditCardsAware: true,
    cardStatementsAware: facts,
  );
  Future<UpgradeRequest> plan() =>
      planCardStatementUpgrade(target, op(), PublicId.generate());
  Future<UpgradeReceipt> upgrade(
    UpgradeRequest request, {
    void Function(String)? checkpoint,
  }) => upgradeCardStatements(
    target,
    request,
    backups,
    password: password,
    recoveryKey: recoveryKey,
    checkpoint: checkpoint,
  );

  setUp(() async {
    work = root.createTempSync('case-');
    backups = Directory('${work.path}/backups')..createSync();
    keys = FixtureKeySlots(Directory('${work.path}/keys'));
    workspace = WorkspaceId(PublicId.generate());
    source = ledger('store', keys, facts: false);
    await source.initialize(op());
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
    charge = Posting.expense(
      id: PublicId.generate(),
      operation: operation(),
      date: BusinessDate(2026, 9, 29),
      account: ref(card),
      amount: Money.parse(twd, '12.34'),
    );
    payment = Posting.transfer(
      id: PublicId.generate(),
      operation: operation(),
      date: BusinessDate(2026, 9, 30),
      source: ref(bank),
      destination: ref(card),
      principal: Money.parse(twd, '5'),
    );
    await source.withSession((session) async {
      await session.createAccount(
        card,
        Posting.opening(
          id: PublicId.generate(),
          operation: operation(),
          date: card.openedOn,
          account: ref(card),
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
      await session.createAccount(
        bank,
        Posting.opening(
          id: PublicId.generate(),
          operation: operation(),
          date: bank.openedOn,
          account: ref(bank),
          amount: Money.parse(twd, '100'),
        ),
      );
      await session.postCardPurchase(charge);
      await session.postCardPayment(payment);
    });
    final legacyBackup = await source.backup(password);
    recoveryKey = legacyBackup.recoveryKey;
    legacyEnvelope = legacyBackup.envelope;
    target = ledger('store', keys, facts: true);
  });
  tearDown(() {
    final base = root.resolveSymbolicLinksSync();
    final resolved = work.resolveSymbolicLinksSync();
    if (!resolved.startsWith('$base${Platform.pathSeparator}')) {
      throw StateError('Unsafe synthetic cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test(
    'schema 17 charge and payment become unallocated schema 18 facts',
    () async {
      final before = await source.snapshot();
      final request = await plan();
      final receipt = await upgrade(request);
      expect(receipt.target.generation, isNot(request.sourceGeneration));
      final snapshot = await target.snapshot();
      final root = jsonDecode(utf8.decode(snapshot)) as Map;
      expect(root['schema'], 18);
      final tables = root['tables'] as Map;
      expect(tables['card_posted_charges'], [
        {
          'workspace': workspace.toString(),
          'event_id': charge.id.value,
          'card_id': card.id.value,
          'posted_on': charge.date.toString(),
          'amount_minor': '1234',
        },
      ]);
      expect(tables['card_payments'], [
        {
          'workspace': workspace.toString(),
          'event_id': payment.id.value,
          'card_id': card.id.value,
          'posted_on': payment.date.toString(),
          'amount_minor': '500',
        },
      ]);
      expect(tables['card_statements'], isEmpty);
      expect(tables['card_payment_allocations'], isEmpty);
      await target.withSession((session) async {
        final balances = {
          for (final row in await session.accounts(workspace))
            row.account.id: row.balance,
        };
        expect(balances[card.id], Money.parse(twd, '-7.34'));
        expect(balances[bank.id], Money.parse(twd, '95'));
        expect(
          (await session.unallocatedCardPayments(
            workspace: workspace,
            cardId: card.id,
          )).single.unallocated,
          Money.parse(twd, '5'),
        );
        expect(
          await session.confirmedCardStatements(
            workspace: workspace,
            cardId: card.id,
          ),
          isEmpty,
        );
      });
      final backupFile = File(
        '${backups.path}/${request.backupId.value}.envelope',
      );
      expect(backupFile.existsSync(), isTrue);
      expect(utf8.decode(before), isNot(utf8.decode(snapshot)));
      final upgradedBackup = await target.backup(password);
      for (final method in ['password', 'recovery']) {
        final slots = FixtureKeySlots(Directory('${work.path}/$method-keys'));
        final restored = ledger(method, slots, facts: true);
        await restored.restore(
          upgradedBackup.envelope,
          op(),
          password: method == 'password' ? password : null,
          recoveryKey: method == 'recovery' ? upgradedBackup.recoveryKey : null,
        );
        expect(await restored.snapshot(), snapshot);
      }
    },
  );

  test(
    'staging failure retains schema 17 and retries same safety backup',
    () async {
      final before = await source.snapshot();
      final request = await plan();
      await expectLater(
        upgrade(
          request,
          checkpoint: (point) {
            if (point.contains('table:card_posted_charges')) {
              throw StateError('synthetic staged failure');
            }
          },
        ),
        throwsA(isA<GenerationUnavailable>()),
      );
      expect(await source.snapshot(), before);
      expect(
        (await source.generations.current())!.receipt.generation,
        request.sourceGeneration,
      );
      final safety = File('${backups.path}/${request.backupId.value}.envelope');
      expect(safety.existsSync(), isTrue);
      final safetyBytes = safety.readAsBytesSync();
      await upgrade(request);
      expect(safety.readAsBytesSync(), safetyBytes);
      expect(
        (jsonDecode(utf8.decode(await target.snapshot())) as Map)['schema'],
        18,
      );
    },
  );

  test(
    'unsupported historical card income fails closed without publication',
    () async {
      await source.generations.withCurrent((file, key, receipt) async {
        final db = openEncrypted(
          file,
          key,
          storageBinding: StorageBinding(
            receipt.generation,
            receipt.slot,
            receipt.operation,
            receipt.fingerprint,
          ),
          categoryAware: true,
          categoryReferences: true,
          tagsAware: true,
          merchantsAware: true,
          transfersAware: true,
          fxTransfersAware: true,
          refundsAware: true,
          reversalsAware: true,
          notesAware: true,
          correctionsAware: true,
          tombstonesAware: true,
          budgetsAware: true,
          recurringAware: true,
          creditCardsAware: true,
        );
        try {
          await FinancialWorkflows(db).post(
            Posting.income(
              id: PublicId.generate(),
              operation: operation(),
              date: BusinessDate(2026, 10, 1),
              account: ref(card),
              amount: Money.parse(twd, '1'),
            ),
          );
        } finally {
          await db.close();
        }
      });
      final before = await source.snapshot();
      final request = await plan();
      await expectLater(
        upgrade(request),
        throwsA(isA<GenerationUnavailable>()),
      );
      expect(await source.snapshot(), before);
      expect(
        (await source.generations.current())!.receipt.generation,
        request.sourceGeneration,
      );
    },
  );

  test('schema 17 backup cannot skip staged migration into schema 18', () async {
    final directKeys = FixtureKeySlots(Directory('${work.path}/direct-keys'));
    final direct = ledger('direct', directKeys, facts: true);
    await expectLater(
      direct.restore(legacyEnvelope, op(), password: password),
      throwsA(isA<GenerationUnavailable>()),
    );
    expect(await direct.generations.current(), isNull);
    // The live schema 17 source can still take the explicit safety-backed path.
    final request = await plan();
    await upgrade(request);
    expect(
      (jsonDecode(utf8.decode(await target.snapshot())) as Map)['schema'],
      18,
    );
  });
}
