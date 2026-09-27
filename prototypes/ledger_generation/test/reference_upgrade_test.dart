import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:crypto/crypto.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:ledger_generation_probe/safety_backup.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

import 'support/reference_fixture.dart';

void main() {
  final root = Directory('.dart_tool/reference-upgrade-tests')
    ..createSync(recursive: true);
  late ReferenceFixture f;
  final unavailable = throwsA(isA<GenerationUnavailable>());
  setUp(() async {
    f = ReferenceFixture(root.createTempSync('case-'));
    await f.initialize();
  });
  tearDown(() => removeReferenceFixture(root, f.directory));

  Future<void> sourceIntact() async {
    final contents = await LedgerPayload(categoryAware: true).inspect(
      f.store().generations.databaseFile(f.original.generation),
      await f.keys.read(f.original.slot),
      f.original,
    );
    expect(utf8.encode(contents), f.before);
  }

  Future<void> backupIntact() async {
    final envelope = await f.backupFile.readAsString();
    expect(
      await EnvelopeCodec().openWithPassword(envelope, referencePassword),
      f.before,
    );
    expect(
      await EnvelopeCodec().openWithRecovery(
        envelope,
        f.credential.recoveryKey,
      ),
      f.before,
    );
  }

  test(
    'schema 4 remains readable but new writes wait for explicit upgrade',
    () async {
      expect(await f.store().snapshot(), f.before);
      await expectLater(
        f.store().withSession((s) => s.post(f.income())),
        throwsStateError,
      );
      await expectLater(f.store().post(f.income()), unavailable);
      await sourceIntact();
      expect(f.backups.listSync(), isEmpty);
    },
  );

  test('upgrade preserves source bytes and shared publication protects later replay', () async {
    final sourceFile = f.store().generations.databaseFile(
      f.original.generation,
    );
    final bytes = sourceFile.readAsBytesSync();
    final receipt = await f.upgrade();
    expect(await f.store().snapshot(), f.expected);
    expect(receipt.target.generation, isNot(f.original.generation));
    expect(receipt.target.slot, isNot(f.original.slot));
    expect(
      receipt.backupDigest,
      sha256.convert(f.backupFile.readAsBytesSync()).toString(),
    );
    await backupIntact();
    await sourceIntact();
    expect(sourceFile.readAsBytesSync(), bytes);
    await expectLater(f.store(references: false).snapshot(), unavailable);
    await f.store().withSession((s) async {
      expect((await s.post(f.priorIncome)).replayed, isTrue);
      await s.post(f.income());
      await s.post(f.expense());
    });
    final later = await f.store().snapshot();
    final backup = await f.store().backup(referencePassword);
    final installed = await f.store().restore(
      backup.envelope,
      newOperation(),
      password: referencePassword,
    );
    expect((await f.upgrade()).target.generation, receipt.target.generation);
    expect(
      (await f.store().generations.current())!.receipt.generation,
      installed.generation,
    );
    expect(await f.store().snapshot(), later);
    expect(await f.store().balance(f.reference), f.money('130'));
    final safety = await createSafetyBackup(
      f.store(),
      f.backups,
      PublicId.generate(),
      password: referencePassword,
      recoveryKey: f.credential.recoveryKey,
    );
    expect(
      await EnvelopeCodec().openWithRecovery(
        await safety.file.readAsString(),
        f.credential.recoveryKey,
      ),
      later,
    );
  });

  test(
    'metadata edits invalidate source digest before creating backup or stage',
    () async {
      await f
          .store(references: false)
          .withSession(
            (s) => s.renameCategory(f.operation(), f.food, 1, '餐飲更新'),
          );
      final current = await f.store().snapshot();
      await expectLater(
        f.upgrade(),
        throwsA(
          isA<GenerationUnavailable>().having(
            (e) => e.problem,
            'reason',
            GenerationProblem.operationConflict,
          ),
        ),
      );
      expect(f.backups.listSync(), isEmpty);
      expect(await f.store().snapshot(), current);
    },
  );

  test('route cannot silently skip versions or publish a different target manifest', () async {
    expect(
      () => upgradeCategories(
        f.store(),
        f.request,
        f.backups,
        password: referencePassword,
        recoveryKey: f.credential.recoveryKey,
      ),
      throwsA(isA<InvalidSnapshot>()),
    );
    expect(
      () => upgradeCategoryReferences(
        f.store(references: false),
        f.request,
        f.backups,
        password: referencePassword,
        recoveryKey: f.credential.recoveryKey,
      ),
      throwsA(isA<InvalidSnapshot>()),
    );
    final invalid = jsonDecode(f.request.encode()) as List;
    invalid[4] = 'ledger-3-to-4-v1';
    expect(
      () => upgradeCategoryReferences(
        f.store(),
        UpgradeRequest.decode(jsonEncode(invalid)),
        f.backups,
        password: referencePassword,
        recoveryKey: f.credential.recoveryKey,
      ),
      throwsA(isA<InvalidSnapshot>()),
    );
    final legacyKeys = FixtureKeySlots(
      Directory('${f.directory.path}/legacy-keys'),
    );
    final legacy = LedgerStore(
      Directory('${f.directory.path}/legacy'),
      legacyKeys,
      catalogProtection: fixtureCatalogProtection(legacyKeys),
    );
    await legacy.initialize(newOperation());
    final capable = LedgerStore(
      legacy.generations.directory,
      legacyKeys,
      catalogProtection: fixtureCatalogProtection(legacyKeys),
      categoryReferences: true,
    );
    await expectLater(
      planCategoryReferenceUpgrade(
        capable,
        newOperation(),
        PublicId.generate(),
      ),
      throwsA(isA<InvalidSnapshot>()),
    );
    expect(f.backups.listSync(), isEmpty);
  });

  test('backup retry requires original credentials and rejects altered envelope bytes', () async {
    await expectLater(
      f.upgrade(
        checkpoint: (point) {
          if (point == 'reserved') throw StateError('synthetic reply loss');
        },
      ),
      unavailable,
    );
    final original = f.backupFile.readAsBytesSync();
    await expectLater(
      upgradeCategoryReferences(
        f.store(),
        f.request,
        f.backups,
        password: 'incorrect-but-long-password',
        recoveryKey: f.credential.recoveryKey,
      ),
      unavailable,
    );
    expect(f.backupFile.readAsBytesSync(), original);
    final replacement = await EnvelopeCodec().create(
      f.before,
      password: referencePassword,
      recoveryKey: f.credential.recoveryKey,
    );
    f.backupFile.writeAsStringSync(replacement.envelope, flush: true);
    await expectLater(
      f.upgrade(),
      throwsA(
        isA<GenerationUnavailable>().having(
          (e) => e.problem,
          'reason',
          GenerationProblem.operationConflict,
        ),
      ),
    );
    expect(await f.store().snapshot(), f.before);
    await sourceIntact();
  });

  for (final point in [
    'backup:created',
    'backup:written',
    'backup:verified',
    'upgradeRecording',
    'reserved',
    'table:allocations',
    'table:category_changes',
    'staged',
    'validated',
    'publishing',
    'published',
  ]) {
    test(
      'fresh process exit at $point leaves complete source or target and safe retry',
      () async {
        final child = await f.childUpgrade(point);
        expect(child.exitCode, 73, reason: child.stderr.toString());
        expect(
          await f.store().snapshot(),
          point == 'published' ? f.expected : f.before,
        );
        await sourceIntact();
        final saved = f.backupFile.readAsBytesSync();
        if (point == 'backup:created') {
          expect(saved, isEmpty);
          await expectLater(f.upgrade(), unavailable);
          expect(f.backupFile.readAsBytesSync(), saved);
          await f.plan();
        } else {
          await backupIntact();
        }
        final retried = await f.childUpgrade('none');
        expect(retried.exitCode, 0, reason: retried.stderr.toString());
        expect(await f.store().snapshot(), f.expected);
        if (point != 'backup:created')
          expect(f.backupFile.readAsBytesSync(), saved);
        expect(
          (await f.upgrade()).target.generation,
          (await f.store().generations.current())!.receipt.generation,
        );
        await sourceIntact();
      },
    );
  }

  for (final sourceBackup in [true, false]) {
    for (final recovery in [false, true]) {
      test(
        'deleted source and keys: ${sourceBackup ? 'safety' : 'live allocated'} backup restores with ${recovery ? 'recovery' : 'password'} alone',
        () async {
          await f.upgrade();
          final posting = f.expense();
          late List<int> expected;
          late File envelope;
          if (sourceBackup) {
            expected =
                f.expected; // Known old snapshot converts during restore.
            envelope = f.backupFile;
          } else {
            await f.store().withSession((s) async {
              await s.post(posting);
              await s.mergeCategory(
                f.operation(),
                sourceId: f.food,
                expectedSourceVersion: 1,
                targetId: f.travel,
                expectedTargetVersion: 1,
              );
              await s.archiveCategory(
                f.operation(),
                f.travel,
                1,
                archived: true,
              );
            });
            expected = await f.store().snapshot();
            final saved = await f.store().backup(
              referencePassword,
              recoveryKey: f.credential.recoveryKey,
            );
            envelope = File('${f.backups.path}/live.envelope')
              ..writeAsStringSync(saved.envelope);
          }
          removeReferenceFixture(root, f.store().generations.directory);
          removeReferenceFixture(root, f.keys.directory);
          final credential = File('${f.directory.path}/single.txt')
            ..writeAsStringSync(
              recovery ? f.credential.recoveryKey : referencePassword,
            );
          final output = File('${f.directory.path}/restored.json');
          final target = f.target('fresh');
          final child = await referenceWorker([
            target.generations.directory.absolute.path,
            '${f.directory.absolute.path}/fresh-keys',
            envelope.absolute.path,
            credential.absolute.path,
            newOperation().toString(),
            recovery ? 'recovery' : 'password',
            'none',
            output.absolute.path,
            'references',
          ]);
          expect(child.exitCode, 0, reason: child.stderr.toString());
          expect(output.readAsBytesSync(), expected);
          expect(await target.snapshot(), expected);
          await target.withSession((s) async {
            expect(
              (await s.post(sourceBackup ? f.priorIncome : posting)).replayed,
              isTrue,
            );
            if (!sourceBackup) {
              expect(
                await s.allocations(f.workspace, posting.id),
                hasLength(2),
              );
              expect(
                (await s.categories(f.workspace)).resolve(f.food).archived,
                isTrue,
              );
            }
          });
          expect(await target.snapshot(), expected);
        },
      );
    }
  }
}
