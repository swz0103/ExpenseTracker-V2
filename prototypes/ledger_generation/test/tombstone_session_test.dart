import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:ledger_generation_probe/safety_backup.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/tombstone-session-tests')
    ..createSync(recursive: true);
  const password = 'synthetic-tombstone-backup-only';
  final currency = Currency('USD', 2);
  final date = BusinessDate(2026, 9, 28);
  late Directory work;
  late FixtureKeySlots keys;
  late WorkspaceId workspace;
  late Account account;
  late Posting original;
  late PostingTombstone deletion;

  OperationId operationId() => OperationId(PublicId.generate());
  OperationKey op() => OperationKey(workspace, operationId());
  Money money(String value) => Money.parse(currency, value);
  PostingAccount ref() => PostingAccount(
    id: account.id,
    workspace: workspace,
    currency: currency,
    expectedVersion: account.version,
  );
  LedgerStore store({bool tombstones = true}) => LedgerStore(
    Directory('${work.path}/store'),
    keys,
    catalogProtection: fixtureCatalogProtection(keys),
    correctionsAware: true,
    tombstonesAware: tombstones,
  );

  Future<void> seed(LedgerStore target) async {
    await target.initialize(operationId());
    await target.withSession((session) async {
      await session.createAccount(
        account,
        Posting.opening(
          id: PublicId.generate(),
          operation: op(),
          date: date,
          account: ref(),
          amount: money('100'),
        ),
      );
      await session.post(original);
    });
  }

  setUp(() {
    work = root.createTempSync('case-');
    keys = FixtureKeySlots(Directory('${work.path}/keys'));
    workspace = WorkspaceId(PublicId.generate());
    account = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'synthetic',
      kind: AccountKind.bank,
      currency: currency,
      openedOn: date,
    );
    original = Posting.expense(
      id: PublicId.generate(),
      operation: op(),
      date: date,
      account: ref(),
      amount: money('10'),
    );
    deletion = PostingTombstone(
      original: original,
      operation: op(),
      reason: 'duplicate entry',
    );
  });
  tearDown(() {
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test('effective list and balance exclude deletion; history and both clean restores retain it', () async {
    final active = store();
    await seed(active);
    await active.withSession((session) async {
      expect((await session.tombstone(deletion)).replayed, false);
      expect((await session.tombstone(deletion)).replayed, true);
      expect((await session.accounts(workspace)).single.balance, money('100'));
      expect(await session.entries(workspace), hasLength(1));
      expect((await session.deletedEntries(workspace)).single.id, original.id);
      expect(
        (await session.entry(workspace, original.id))!.tombstoneReason,
        'duplicate entry',
      );
      expect(
        (await session.activity(
          workspace,
          original.id,
        )).where((row) => row.auditKind == 'ledger.tombstone'),
        hasLength(1),
      );
    });
    final before = await active.snapshot();
    final backup = await active.backup(password);
    final safety = Directory('${work.path}/safety')..createSync();
    final verified = await createSafetyBackup(
      active,
      safety,
      PublicId.generate(),
      password: password,
      recoveryKey: backup.recoveryKey,
    );
    expect(
      await EnvelopeCodec().openWithPassword(
        await verified.file.readAsString(),
        password,
      ),
      before,
    );
    Directory('${work.path}/store').deleteSync(recursive: true);
    Directory('${work.path}/keys').deleteSync(recursive: true);
    for (final method in ['password', 'recovery']) {
      final slots = FixtureKeySlots(Directory('${work.path}/$method-keys'));
      final restored = LedgerStore(
        Directory('${work.path}/$method'),
        slots,
        catalogProtection: fixtureCatalogProtection(slots),
        correctionsAware: true,
        tombstonesAware: true,
      );
      await restored.restore(
        backup.envelope,
        operationId(),
        password: method == 'password' ? password : null,
        recoveryKey: method == 'recovery' ? backup.recoveryKey : null,
      );
      expect(await restored.snapshot(), before);
      await restored.withSession((session) async {
        expect((await session.tombstone(deletion)).replayed, true);
        expect(
          (await session.accounts(workspace)).single.balance,
          money('100'),
        );
        expect(await session.entries(workspace), hasLength(1));
        expect(
          (await session.deletedEntries(workspace)).single.id,
          original.id,
        );
      });
    }
  });

  test('schema 13 to 14 failed upgrade retains source, verified safety backup, then publishes', () async {
    final old = store(tombstones: false);
    await seed(old);
    final oldReceipt = (await old.generations.current())!.receipt;
    final before = await old.snapshot();
    final credential = await old.backup(password);
    final target = store();
    final backupId = PublicId.generate();
    final request = await planTombstoneUpgrade(target, operationId(), backupId);
    final backupDirectory = Directory('${work.path}/safety')..createSync();
    await expectLater(
      upgradeTombstones(
        target,
        request,
        backupDirectory,
        password: password,
        recoveryKey: credential.recoveryKey,
        checkpoint: (point) {
          if (point == 'table:event_tombstones') throw StateError('injected');
        },
      ),
      throwsA(isA<GenerationUnavailable>()),
    );
    expect(await target.snapshot(), before);
    final safety = File('${backupDirectory.path}/${backupId.value}.envelope');
    final envelope = await safety.readAsString();
    expect(await EnvelopeCodec().openWithPassword(envelope, password), before);
    expect(
      await EnvelopeCodec().openWithRecovery(envelope, credential.recoveryKey),
      before,
    );
    await upgradeTombstones(
      target,
      request,
      backupDirectory,
      password: password,
      recoveryKey: credential.recoveryKey,
    );
    expect(
      await target.snapshot(),
      SnapshotCodec(
        correctionsAware: true,
        tombstonesAware: true,
      ).canonicalize(before),
    );
    expect(
      utf8.encode(
        await LedgerPayload(correctionsAware: true).inspect(
          target.generations.databaseFile(oldReceipt.generation),
          await keys.read(oldReceipt.slot),
          oldReceipt,
        ),
      ),
      before,
    );
    await target.withSession((session) async {
      await session.tombstone(deletion);
      expect((await session.accounts(workspace)).single.balance, money('100'));
    });
  });
}
