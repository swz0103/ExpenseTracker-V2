import 'dart:io';
import 'dart:convert';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:storage_generation_probe/generation_store.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/tombstone-engine-tests')
    ..createSync(recursive: true);
  late Directory work;
  late MemoryVault vault;
  late PreviewEngine engine;

  setUp(() {
    work = root.createTempSync('case-');
    vault = MemoryVault();
    engine = engineAt(work, vault, schemaVersion: 14);
  });
  tearDown(() async {
    await engine.lock();
    deleteSynthetic(work, root);
  });

  test(
    'App 14 uses one capability contract for effective entries and history',
    () async {
      await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      final original = income(a);
      await engine.post(original);
      final command = PostingTombstone(
        original: original,
        operation: OperationKey(
          engine.workspace,
          OperationId(PublicId.generate()),
        ),
        reason: 'duplicate',
      );
      await engine.tombstone(command);
      await engine.tombstone(command);
      expect(
        (await engine.accounts()).single.balance,
        Money.parse(a.currency, '100'),
      );
      expect(await engine.entries(), hasLength(1));
      expect(
        (await engine.activity(original.id))
            .where((row) => row.auditKind == 'ledger.tombstone'),
        hasLength(1),
      );
      expect(await engine.exportBackup(), isNotEmpty);
      await engine.lock();
      await engine.unlock(password);
      expect(
        (await engine.accounts()).single.balance,
        Money.parse(a.currency, '100'),
      );
    },
  );

  for (final recovery in [false, true]) {
    test(
      'clean ${recovery ? 'recovery' : 'password'} restore retains tombstone, audit and replay boundary',
      () async {
        final key = await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        final original = income(a);
        await engine.post(original);
        final command = PostingTombstone(
          original: original,
          operation: OperationKey(
            engine.workspace,
            OperationId(PublicId.generate()),
          ),
          reason: 'duplicate',
        );
        await engine.tombstone(command);
        final backup = await engine.exportBackup();
        final snapshot = jsonDecode(
          utf8.decode(await EnvelopeCodec().openWithPassword(backup, password)),
        ) as Map<String, dynamic>;
        final tables = snapshot['tables'] as Map<String, dynamic>;
        expect(tables['event_tombstones'], hasLength(1));
        expect(
          (tables['audit'] as List).where(
            (row) => row['kind'] == 'ledger.tombstone',
          ),
          hasLength(1),
        );

        final target = root.createTempSync('clean-');
        final restored = engineAt(target, MemoryVault(), schemaVersion: 14);
        try {
          await setup(restored);
          await restored.importBackup(
            backup,
            recovery ? key : password,
            recovery: recovery,
          );
          expect(
            (await restored.accounts()).single.balance,
            Money.parse(a.currency, '100'),
          );
          expect(await restored.entries(), hasLength(1));
          final history = await restored.activity(original.id);
          expect(
            history.where((row) => row.auditKind == 'ledger.tombstone'),
            hasLength(1),
          );
          await restored.tombstone(command);
          expect(
            (await restored.accounts()).single.balance,
            Money.parse(a.currency, '100'),
          );
          expect(
            (await restored.activity(original.id))
                .where((row) => row.auditKind == 'ledger.tombstone'),
            hasLength(1),
          );
          expect(await restored.hasSafetyCopy(), isTrue);
        } finally {
          await restored.lock();
          deleteSynthetic(target, root);
        }
      },
    );
  }

  test('schema 14 rejects damaged and future backups before replacing the active ledger', () async {
    await setup(engine);
    final a = account(engine);
    await engine.createAccount(a, opening(a));
    final original = income(a);
    await engine.post(original);
    await engine.tombstone(
      PostingTombstone(
        original: original,
        operation: OperationKey(
          engine.workspace,
          OperationId(PublicId.generate()),
        ),
        reason: 'duplicate',
      ),
    );
    final backup = await engine.exportBackup();
    final decoded = jsonDecode(
      utf8.decode(await EnvelopeCodec().openWithPassword(backup, password)),
    ) as Map<String, dynamic>;
    decoded['version'] = 999;
    final future = await EnvelopeCodec().create(
      utf8.encode(jsonEncode(decoded)),
      password: password,
    );

    await expectLater(
      engine.importBackup(
        backup.substring(0, backup.length ~/ 2),
        password,
        recovery: false,
      ),
      throwsA(anything),
    );
    await expectLater(
      engine.importBackup(future.envelope, password, recovery: false),
      throwsA(anything),
    );
    expect(await engine.hasSafetyCopy(), isFalse);
    expect(
      (await engine.accounts()).single.balance,
      Money.parse(a.currency, '100'),
    );
    expect(await engine.entries(), hasLength(1));
    expect(
      (await engine.activity(original.id))
          .where((row) => row.auditKind == 'ledger.tombstone'),
      hasLength(1),
    );
    expect(await engine.exportBackup(), isNotEmpty);
  });

  test(
    'App 13 to 14 failure keeps old reader usable and retry publishes',
    () async {
      engine = engineAt(work, vault, schemaVersion: 13);
      await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      final original = income(a);
      await engine.post(original);
      await engine.lock();

      engine = engineAt(
        work,
        vault,
        schemaVersion: 14,
        checkpoint: (point) {
          if (point == '13:table:event_tombstones') {
            throw StateError('injected');
          }
        },
      );
      await expectLater(
        engine.unlock(password),
        throwsA(isA<PreviewUpgradeRequired>()),
      );
      await expectLater(
        engine.upgrade(password),
        throwsA(isA<GenerationUnavailable>()),
      );
      await engine.lock();
      engine = engineAt(work, vault, schemaVersion: 13);
      await engine.unlock(password);
      expect(
        (await engine.accounts()).single.balance,
        Money.parse(a.currency, '107'),
      );
      expect(await engine.exportBackup(), isNotEmpty);
      await engine.lock();

      engine = engineAt(work, vault, schemaVersion: 14);
      await engine.upgrade(password);
      expect(engine.capabilities.tombstones, true);
      await engine.tombstone(
        PostingTombstone(
          original: original,
          operation: OperationKey(
            engine.workspace,
            OperationId(PublicId.generate()),
          ),
        ),
      );
      expect(
        (await engine.accounts()).single.balance,
        Money.parse(a.currency, '100'),
      );
    },
  );

  test(
    'encrypted deletion draft survives preparation and commit-without-response',
    () async {
      await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      final original = income(a);
      await engine.post(original);
      final saved = await engine.saveEntryDraft(
        EntryFields(
          income: false,
          amount: '',
          date: '',
          tombstoneOf: original.id,
          tombstoneReason: 'duplicate',
        ),
      );
      await engine.lock();
      String? stop = 'draft-prepared';
      PreviewEngine reopen() => engineAt(
        work,
        vault,
        schemaVersion: 14,
        draftCheckpoint: (point) {
          if (point == stop) throw StateError('injected');
        },
      );
      engine = reopen();
      await engine.unlock(password);
      expect((await engine.entryDraft())!.encode(), saved.encode());
      await expectLater(engine.submitEntryDraft(), throwsStateError);
      final prepared = (await engine.entryDraft())!;
      expect(prepared.tombstoneSubmission, isNotNull);
      expect(
        (await engine.accounts()).single.balance,
        Money.parse(a.currency, '107'),
      );
      await engine.lock();
      stop = 'draft-committed';
      engine = reopen();
      await engine.unlock(password);
      expect((await engine.entryDraft())!.encode(), prepared.encode());
      await expectLater(engine.submitEntryDraft(), throwsStateError);
      expect(await engine.entryDraft(), isNull);
      expect(
        (await engine.accounts()).single.balance,
        Money.parse(a.currency, '100'),
      );
      expect(await engine.entries(), hasLength(1));
    },
  );
}
