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
import 'package:validated_restore_probe/snapshot.dart';
import 'package:test/test.dart';

const password = 'synthetic-card-authorization-upgrade-password';

void main() {
  final root = Directory('.dart_tool/card-authorization-upgrade-tests')
    ..createSync(recursive: true);
  final twd = Currency('TWD', 2);
  late Directory work, backups;
  late FixtureKeySlots keys;
  late LedgerStore source, target;
  late WorkspaceId workspace;
  late Account card;
  late String recoveryKey;

  OperationId op() => OperationId(PublicId.generate());
  OperationKey operation() => OperationKey(workspace, op());
  PostingAccount ref() => PostingAccount(
    id: card.id,
    workspace: workspace,
    currency: card.currency,
    expectedVersion: card.version,
  );
  LedgerStore ledger(
    String name,
    FixtureKeySlots slots, {
    required bool auth,
  }) => LedgerStore(
    Directory('${work.path}/$name'),
    slots,
    catalogProtection: fixtureCatalogProtection(slots),
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
    creditCardsAware: true,
    cardStatementsAware: true,
    cardAuthorizationsAware: auth,
  );
  Future<UpgradeRequest> plan() =>
      planCardAuthorizationUpgrade(target, op(), PublicId.generate());
  Future<UpgradeReceipt> upgrade(
    UpgradeRequest request, {
    void Function(String)? checkpoint,
  }) => upgradeCardAuthorizations(
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
    source = ledger('store', keys, auth: false);
    await source.initialize(op());
    card = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic card',
      kind: AccountKind.creditCard,
      currency: twd,
      openedOn: BusinessDate(2026, 1, 1),
    );
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
          id: PublicId.generate(),
          operation: operation(),
          date: BusinessDate(2026, 9, 29),
          account: ref(),
          amount: Money.parse(twd, '12.34'),
        ),
      );
      await session.confirmCardStatement(
        workspace: workspace,
        statementId: PublicId.generate(),
        cardId: card.id,
        revision: 1,
        cycle: CardCycle(
          startsAfter: BusinessDate(2026, 9, 28),
          closesOn: BusinessDate(2026, 10, 28),
          dueOn: BusinessDate(2026, 11, 15),
        ),
        billed: Money.parse(twd, '12.34'),
        operation: op(),
      );
    });
    final backup = await source.backup(password);
    recoveryKey = backup.recoveryKey;
    target = ledger('store', keys, auth: true);
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
    'schema 18 facts survive, schema 19 starts with no invented pending',
    () async {
      final before = jsonDecode(utf8.decode(await source.snapshot())) as Map;
      final request = await plan();
      final receipt = await upgrade(request);
      expect(receipt.target.generation, isNot(request.sourceGeneration));
      final bytes = await target.snapshot();
      final after = jsonDecode(utf8.decode(bytes)) as Map;
      expect(after['schema'], 19);
      final oldTables = before['tables'] as Map;
      final newTables = after['tables'] as Map;
      for (final name in oldTables.keys) {
        expect(newTables[name], oldTables[name], reason: '$name changed');
      }
      expect(newTables['card_authorizations'], isEmpty);
      expect(newTables['card_authorization_resolutions'], isEmpty);
      expect(
        File('${backups.path}/${request.backupId.value}.envelope').existsSync(),
        isTrue,
      );
      final safetyEnvelope = await File(
        '${backups.path}/${request.backupId.value}.envelope',
      ).readAsString();
      final codec = EnvelopeCodec();
      expect(
        jsonDecode(
          utf8.decode(await codec.openWithPassword(safetyEnvelope, password)),
        ),
        before,
      );
      expect(
        jsonDecode(
          utf8.decode(
            await codec.openWithRecovery(safetyEnvelope, recoveryKey),
          ),
        ),
        before,
      );
      final upgradedBackup = await target.backup(password);
      for (final method in ['password', 'recovery']) {
        final slots = FixtureKeySlots(Directory('${work.path}/$method-keys'));
        final restored = ledger(method, slots, auth: true);
        await restored.restore(
          upgradedBackup.envelope,
          op(),
          password: method == 'password' ? password : null,
          recoveryKey: method == 'recovery' ? upgradedBackup.recoveryKey : null,
        );
        expect(await restored.snapshot(), bytes);
      }
    },
  );

  test(
    'staging interruption retains schema 18 and reuses safety backup',
    () async {
      final before = await source.snapshot();
      final request = await plan();
      await expectLater(
        upgrade(
          request,
          checkpoint: (point) {
            if (point.contains('table:card_authorizations')) {
              throw StateError('synthetic staged interruption');
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
        19,
      );
    },
  );

  test('schema 18 backup cannot silently skip the explicit upgrade', () async {
    final oldBackup = await source.backup(password);
    final directKeys = FixtureKeySlots(Directory('${work.path}/direct-keys'));
    final direct = ledger('direct', directKeys, auth: true);
    await expectLater(
      direct.restore(oldBackup.envelope, op(), password: password),
      throwsA(isA<InvalidSnapshot>()),
    );
    expect(await direct.generations.current(), isNull);
    final request = await plan();
    await upgrade(request);
    expect(
      (jsonDecode(utf8.decode(await target.snapshot())) as Map)['schema'],
      19,
    );
  });
}
