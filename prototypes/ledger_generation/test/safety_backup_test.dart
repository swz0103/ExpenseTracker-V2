import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:ledger_generation_probe/safety_backup.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:storage_generation_probe/lock_wait.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

const password = 'synthetic-safety-backup-only';

void main() {
  final root = Directory('.dart_tool/safety-tests')
    ..createSync(recursive: true);
  late Directory work;
  late Directory output;
  late LedgerStore store;
  late List<int> expected;
  late CreatedBackup initial;
  setUpAll(() async {
    final fixture = root.createTempSync('source-');
    final file = File('${fixture.path}/source.db');
    final raw = sqlite3.open(file.path);
    raw.execute(
      File('../modular_persistence/test/fixtures/v1.sql').readAsStringSync(),
    );
    raw.close();
    final db = ProbeDatabase(file);
    try {
      final bytes = await SnapshotCodec().capture(db);
      initial = await EnvelopeCodec().create(bytes, password: password);
      expected = SnapshotCodec(generationAware: true).canonicalize(bytes);
    } finally {
      await db.close();
    }
  });
  setUp(() async {
    work = root.createTempSync('case-');
    output = Directory('${work.path}/backups')..createSync();
    store = LedgerStore(
      Directory('${work.path}/source'),
      FixtureKeySlots(Directory('${work.path}/source-keys')),
    );
    await store.restore(
      initial.envelope,
      OperationId(PublicId.generate()),
      password: password,
    );
  });
  tearDown(() {
    final target = work.absolute.path;
    if (!target.startsWith('${root.absolute.path}${Platform.pathSeparator}')) {
      throw StateError('Unsafe fixture cleanup');
    }
    work.deleteSync(recursive: true);
  });
  final unavailable = throwsA(isA<SafetyBackupUnavailable>());
  test('both backup entrypoints explicitly preserve a supplied recovery credential', () async {
    final ordinary = await store.backup(
      password,
      recoveryKey: initial.recoveryKey,
    );
    expect(ordinary.recoveryKey == initial.recoveryKey, isTrue);
    expect(
      await EnvelopeCodec().openWithRecovery(
        ordinary.envelope,
        initial.recoveryKey,
      ),
      expected,
    );
    final safety = await createSafetyBackup(
      store,
      output,
      PublicId.generate(),
      password: password,
      recoveryKey: initial.recoveryKey,
    );
    expect(safety.recoveryKey == initial.recoveryKey, isTrue);
    expect(
      await EnvelopeCodec().openWithRecovery(
        await safety.file.readAsString(),
        initial.recoveryKey,
      ),
      expected,
    );
    expect(await store.snapshot(), expected);
  });
  test(
    'invalid retained recovery credential creates no backup or source change',
    () async {
      await expectLater(
        createSafetyBackup(
          store,
          output,
          PublicId.generate(),
          password: password,
          recoveryKey: 'ETV2-R1-invalid',
        ),
        throwsA(
          isA<BackupException>().having(
            (e) => e.code,
            'code',
            BackupError.invalidFormat,
          ),
        ),
      );
      expect(output.listSync(), isEmpty);
      expect(await store.snapshot(), expected);
    },
  );
  test(
    'backup captures live postings rather than original installation input',
    () async {
      final workspace = WorkspaceId.parse(
        '019f0000-0000-7000-8000-000000000000',
      );
      final account = PostingAccount(
        id: PublicId.parse('019f0000-0000-7000-8000-000000000001'),
        workspace: workspace,
        currency: Currency('USD', 2),
        expectedVersion: 1,
      );
      await store.post(
        Posting.income(
          id: PublicId.generate(),
          operation: OperationKey(workspace, OperationId(PublicId.generate())),
          date: BusinessDate(2026, 9, 27),
          account: account,
          amount: Money.parse(account.currency, '8'),
        ),
      );
      final current = await store.snapshot();
      expect(current, isNot(expected));
      final backup = await createSafetyBackup(
        store,
        output,
        PublicId.generate(),
        password: password,
      );
      final saved = await backup.file.readAsString();
      expect(await EnvelopeCodec().openWithPassword(saved, password), current);
      expect(
        await EnvelopeCodec().openWithRecovery(saved, backup.recoveryKey),
        current,
      );
      expect(
        await store.balance(account),
        Money.parse(account.currency, '123'),
      );
    },
  );
  test('unknown source schema is refused before producing a backup', () async {
    final current = (await store.generations.current())!;
    final file = store.generations.databaseFile(current.receipt.generation);
    final raw = sqlite3.open(file.path);
    try {
      configureEncryption(
        raw,
        await store.generations.keys.read(current.receipt.slot),
      );
      raw.userVersion = 4;
    } finally {
      raw.close();
    }
    final before = await file.readAsBytes();
    await expectLater(
      createSafetyBackup(
        store,
        output,
        PublicId.generate(),
        password: password,
      ),
      throwsA(isA<GenerationUnavailable>()),
    );
    expect(output.listSync(), isEmpty);
    expect(await file.readAsBytes(), before);
  });
  test(
    'persisted bytes open with both credentials and source remains identical',
    () async {
      final prior = await store.generations.current();
      final backup = await createSafetyBackup(
        store,
        output,
        PublicId.generate(),
        password: password,
      );
      final saved = await backup.file.readAsString();
      expect(await EnvelopeCodec().openWithPassword(saved, password), expected);
      expect(
        await EnvelopeCodec().openWithRecovery(saved, backup.recoveryKey),
        expected,
      );
      expect(await store.snapshot(), expected);
      expect(backup.source.generation, prior!.receipt.generation);
      expect(
        (await store.generations.current())!.receipt.generation,
        prior.receipt.generation,
      );
    },
  );
  for (final mode in ['password', 'recovery']) {
    test('persisted safety backup restores in clean $mode process', () async {
      final backup = await createSafetyBackup(
        store,
        output,
        PublicId.generate(),
        password: password,
      );
      final credential = File('${work.path}/credential.txt')
        ..writeAsStringSync(mode == 'password' ? password : backup.recoveryKey);
      final result = File('${work.path}/result.json');
      final executable = File(
        '.dart_tool/worker/bundle/bin/ledger_worker${Platform.isWindows ? '.exe' : ''}',
      );
      final child = await Process.run(executable.absolute.path, [
        '${work.absolute.path}/target',
        '${work.absolute.path}/target-keys',
        backup.file.absolute.path,
        credential.absolute.path,
        OperationId(PublicId.generate()).toString(),
        mode,
        'none',
        result.absolute.path,
      ]);
      expect(child.exitCode, 0);
      expect(await result.readAsBytes(), expected);
    });
  }
  test('existing artifact is never overwritten', () async {
    final id = PublicId.generate();
    final file = File('${output.path}/${id.value}.envelope')
      ..writeAsStringSync('retained');
    await expectLater(
      createSafetyBackup(store, output, id, password: password),
      unavailable,
    );
    expect(file.readAsStringSync(), 'retained');
    expect(await store.snapshot(), expected);
  });
  test(
    'readback tampering is rejected and retained without changing source',
    () async {
      late File artifact;
      await expectLater(
        createSafetyBackup(
          store,
          output,
          PublicId.generate(),
          password: password,
          checkpoint: (point, file) async {
            artifact = file;
            if (point == 'written')
              await file.writeAsString('damaged-fixture', flush: true);
          },
        ),
        unavailable,
      );
      expect(await artifact.readAsString(), 'damaged-fixture');
      expect(await store.snapshot(), expected);
    },
  );
  test(
    'storage failure retains artifact and suppresses underlying path',
    () async {
      final id = PublicId.generate();
      await expectLater(
        createSafetyBackup(
          store,
          output,
          id,
          password: password,
          checkpoint: (point, file) async {
            if (point == 'written')
              throw const FileSystemException('sensitive-path');
          },
        ),
        throwsA(
          isA<SafetyBackupUnavailable>().having(
            (e) => e.toString(),
            'redaction',
            isNot(contains('sensitive-path')),
          ),
        ),
      );
      expect(File('${output.path}/${id.value}.envelope').existsSync(), isTrue);
      await expectLater(
        createSafetyBackup(store, output, id, password: password),
        unavailable,
      );
      expect(await store.snapshot(), expected);
    },
  );
  for (final invalid in ['missing', 'source']) {
    test('rejects $invalid destination', () async {
      final directory = invalid == 'source'
          ? store.generations.directory
          : Directory('${work.path}/missing');
      await expectLater(
        createSafetyBackup(
          store,
          directory,
          PublicId.generate(),
          password: password,
        ),
        unavailable,
      );
      expect(await store.snapshot(), expected);
    });
  }
  test('cancellation while waiting creates no artifact', () async {
    await expectLater(
      createSafetyBackup(
        store,
        output,
        PublicId.generate(),
        password: password,
        cancellation: LockWaitCancellation()..cancel(),
      ),
      throwsA(isA<GenerationUnavailable>()),
    );
    expect(output.listSync(), isEmpty);
  });
  test(
    'lifecycle exclusion remains held until persisted readback completes',
    () async {
      var observed = false;
      await createSafetyBackup(
        store,
        output,
        PublicId.generate(),
        password: password,
        checkpoint: (point, file) async {
          if (point == 'written') {
            await expectLater(
              store.snapshot(),
              throwsA(
                isA<GenerationUnavailable>().having(
                  (e) => e.problem,
                  'problem',
                  GenerationProblem.busy,
                ),
              ),
            );
            observed = true;
          }
        },
      );
      expect(observed, isTrue);
      expect(await store.snapshot(), expected);
    },
  );
  test('invalid password leaves no output', () async {
    await expectLater(
      createSafetyBackup(store, output, PublicId.generate(), password: 'short'),
      throwsA(isA<BackupException>()),
    );
    expect(output.listSync(), isEmpty);
    expect(await store.snapshot(), expected);
  });
}
