import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/restore_store.dart';
import 'package:validated_restore_probe/snapshot.dart';

const password = 'fixture-only-password-2026';
final workspace = WorkspaceId.parse('019f0000-0000-7000-8000-000000000000');
final account = PostingAccount(
  id: PublicId.parse('019f0000-0000-7000-8000-000000000001'),
  workspace: workspace,
  currency: Currency('USD', 2),
  expectedVersion: 1,
);

Future<void> fixture(File file, {bool extraIncome = false}) async {
  file.parent.createSync(recursive: true);
  final legacy = sqlite3.open(file.path);
  try {
    legacy.execute(
      File('../modular_persistence/test/fixtures/v1.sql').readAsStringSync(),
    );
  } finally {
    legacy.close();
  }
  final db = ProbeDatabase(file);
  try {
    final flows = FinancialWorkflows(db);
    await flows.ledger.balance(account); // Upgrade the frozen fixture.
    if (extraIncome) {
      await flows.post(
        Posting.income(
          id: PublicId.generate(),
          operation: OperationKey(workspace, OperationId(PublicId.generate())),
          date: BusinessDate(2026, 9, 26),
          account: account,
          amount: Money.parse(account.currency, '7'),
        ),
      );
    }
  } finally {
    await db.close();
  }
}

void main() {
  final root = Directory('.dart_tool/restore-tests')
    ..createSync(recursive: true);
  late Directory work;
  late RestoreStore store;
  late List<int> sourceBytes;
  late CreatedBackup backup;
  late Directory chunkFixtureRoot;
  late Directory chunkedBackup;
  late String chunkedRecoveryKey;
  setUpAll(() async {
    final seed = root.createTempSync('seed-');
    chunkFixtureRoot = root.createTempSync('chunk-fixture-');
    try {
      final file = File('${seed.path}/source.db');
      await fixture(file);
      final db = ProbeDatabase(file);
      try {
        sourceBytes = await SnapshotCodec().capture(db);
        backup = await RestoreStore(seed).backup(db, password);
        chunkedBackup = Directory('${chunkFixtureRoot.path}/authenticated');
        final created = await RestoreStore(seed)
            .backupChunked(db, chunkedBackup, password: password);
        chunkedRecoveryKey = created.recoveryKey;
      } finally {
        await db.close();
      }
    } finally {
      safeDelete(seed, root);
    }
  });
  tearDownAll(() => safeDelete(chunkFixtureRoot, root));
  setUp(() {
    work = root.createTempSync('case-');
    store = RestoreStore(Directory('${work.path}/owned'));
  });
  tearDown(() => safeDelete(work, root));

  Future<ProcessResult> child(String mode, String checkpoint) async {
    final envelopeFile = File('${work.path}/backup.json')
      ..writeAsStringSync(backup.envelope);
    final credential = File('${work.path}/credential.txt')
      ..writeAsStringSync(mode == 'password' ? password : backup.recoveryKey);
    final executable = File(
      '.dart_tool/worker/bundle/bin/restore_worker${Platform.isWindows ? '.exe' : ''}',
    );
    if (!executable.existsSync())
      throw StateError('Build restore_worker CLI before tests.');
    return Process.run(executable.absolute.path, [
      store.directory.absolute.path,
      envelopeFile.absolute.path,
      credential.absolute.path,
      mode,
      checkpoint,
    ]);
  }

  Future<void> verifyRestored() async {
    final db = ProbeDatabase(store.current);
    try {
      expect(await SnapshotCodec().capture(db), sourceBytes);
      final flows = FinancialWorkflows(db);
      expect(
        await flows.ledger.balance(account),
        Money.parse(account.currency, '115'),
      );
      final retry = await flows.post(
        Posting.income(
          id: PublicId.generate(),
          operation: OperationKey(
            workspace,
            OperationId.parse('019f0000-0000-7000-8000-000000000011'),
          ),
          date: BusinessDate(2026, 9, 26),
          account: account,
          amount: Money.parse(account.currency, '20'),
        ),
      );
      expect(retry.replayed, isTrue);
      expect(await SnapshotCodec().capture(db), sourceBytes);
    } finally {
      await db.close();
    }
  }

  for (final mode in ['password', 'recovery']) {
    test(
      'fresh process restores all authoritative rows with $mode and preserves replay',
      () async {
        final result = await child(mode, 'none');
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        await verifyRestored();
      },
    );
  }
  for (final mode in ['password', 'recovery']) {
    test('chunked restore promotes with $mode and preserves replay', () async {
      await store.restoreChunked(
        chunkedBackup,
        password: mode == 'password' ? password : null,
        recoveryKey: mode == 'recovery' ? chunkedRecoveryKey : null,
      );
      await verifyRestored();
      expect(
        File('${store.directory.path}/journal.json').existsSync(),
        isFalse,
      );
    });
  }
  test(
    'chunked promotion failure at every checkpoint restores old current',
    () async {
      for (final failure in ['validated', 'prepared', 'oldMoved', 'newMoved']) {
        await fixture(store.current, extraIncome: true);
        final before = store.current.readAsBytesSync();
        await expectLater(
          store.restoreChunked(
            chunkedBackup,
            recoveryKey: chunkedRecoveryKey,
            checkpoint: (at) {
              if (at == failure) throw StateError('fixture interruption');
            },
          ),
          throwsStateError,
        );
        expect(store.current.readAsBytesSync(), before, reason: failure);
        expect(
          File('${store.directory.path}/stage.db').existsSync(),
          isFalse,
          reason: failure,
        );
        expect(
          File('${store.directory.path}/journal.json').existsSync(),
          isFalse,
          reason: failure,
        );
        for (final retained
            in store.directory.listSync().whereType<File>().where(
              (file) => file.uri.pathSegments.last.startsWith('uncommitted-'),
            )) {
          retained.deleteSync();
        }
        store.current.deleteSync();
      }
      await store.restoreChunked(
        chunkedBackup,
        recoveryKey: chunkedRecoveryKey,
      );
      await verifyRestored();
    },
  );
  test('successful replacement retains complete previous database', () async {
    await fixture(store.current, extraIncome: true);
    final before = store.current.readAsBytesSync();
    await store.restore(backup.envelope, recoveryKey: backup.recoveryKey);
    await verifyRestored();
    expect(
      File('${store.directory.path}/previous.db').readAsBytesSync(),
      before,
    );
    expect(File('${store.directory.path}/journal.json').existsSync(), isFalse);
  });
  test('wrong password does not alter current file', () async {
    await fixture(store.current, extraIncome: true);
    final before = store.current.readAsBytesSync();
    await expectLater(
      store.restore(backup.envelope, password: 'wrong-password'),
      throwsA(isA<Exception>()),
    );
    expect(store.current.readAsBytesSync(), before);
  });
  test('truncated ciphertext does not alter current file', () async {
    await fixture(store.current, extraIncome: true);
    final before = store.current.readAsBytesSync();
    await expectLater(
      store.restore(
        backup.envelope.substring(0, backup.envelope.length - 8),
        recoveryKey: backup.recoveryKey,
      ),
      throwsA(isA<Exception>()),
    );
    expect(store.current.readAsBytesSync(), before);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'unknown module': (r) => r['modules']['future'] = 1,
    'unknown schema': (r) => r['schema'] = 3,
    'unknown column': (r) => r['tables']['events'][0]['new_value'] = 'hidden',
    'missing opening': (r) => r['tables']['openings'].clear(),
    'report mismatch': (r) => r['tables']['events'][1]['income'] = '123',
    'currency mismatch': (r) => r['tables']['legs'][1]['currency'] = 'TWD',
    'receipt mismatch': (r) {
      final rows = r['tables']['receipts'];
      final input = jsonDecode(rows[1]['input']);
      input[3][2]['minorUnits'] = '1';
      rows[1]['input'] = jsonEncode(input);
    },
    'missing audit': (r) => r['tables']['audit'].removeLast(),
    'orphan leg': (r) =>
        r['tables']['legs'][1]['account_id'] = PublicId.generate().value,
    'integer overflow': (r) =>
        r['tables']['legs'][1]['amount'] = '9223372036854775808',
  };
  for (final mutation in mutations.entries) {
    test(
      'authenticated but invalid ${mutation.key} rejects before promotion',
      () async {
        await fixture(store.current, extraIncome: true);
        final before = store.current.readAsBytesSync();
        final rootJson =
            jsonDecode(utf8.decode(sourceBytes)) as Map<String, dynamic>;
        mutation.value(rootJson);
        final invalid = await EnvelopeCodec().create(
          utf8.encode(jsonEncode(rootJson)),
          password: password,
        );
        await expectLater(
          store.restore(invalid.envelope, recoveryKey: invalid.recoveryKey),
          throwsA(anything),
        );
        expect(store.current.readAsBytesSync(), before);
        expect(
          File('${store.directory.path}/journal.json').existsSync(),
          isFalse,
        );
      },
    );
  }
  for (final point in ['validated', 'prepared', 'oldMoved', 'newMoved']) {
    test('exception at $point rolls back and permits later restore', () async {
      await fixture(store.current, extraIncome: true);
      final before = store.current.readAsBytesSync();
      await expectLater(
        store.restore(
          backup.envelope,
          recoveryKey: backup.recoveryKey,
          checkpoint: (at) {
            if (at == point)
              throw const FileSystemException('injected IO failure');
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.current.readAsBytesSync(), before);
      expect(
        File('${store.directory.path}/journal.json').existsSync(),
        isFalse,
      );
      await store.restore(backup.envelope, recoveryKey: backup.recoveryKey);
      await verifyRestored();
    });
  }
  for (final point in ['prepared', 'oldMoved', 'newMoved']) {
    test(
      'process exits at $point; next launch recovers old database idempotently',
      () async {
        await fixture(store.current, extraIncome: true);
        final before = store.current.readAsBytesSync();
        final result = await child('recovery', point);
        expect(
          result.exitCode,
          73,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(
          File('${store.directory.path}/journal.json').existsSync(),
          isTrue,
        );
        await RestoreStore(store.directory).recover();
        await RestoreStore(store.directory).recover();
        expect(store.current.readAsBytesSync(), before);
        await store.restore(backup.envelope, recoveryKey: backup.recoveryKey);
        await verifyRestored();
      },
    );
  }
  test('interrupted first restore leaves no committed database', () async {
    expect((await child('recovery', 'newMoved')).exitCode, 73);
    await store.recover();
    expect(store.current.existsSync(), isFalse);
    expect(
      store.directory.listSync().whereType<File>().where(
        (f) => f.path.contains('uncommitted-'),
      ),
      hasLength(1),
    );
    await store.restore(backup.envelope, recoveryKey: backup.recoveryKey);
    await verifyRestored();
  });
  test('malformed recovery journal fails closed', () async {
    await fixture(store.current, extraIncome: true);
    final before = store.current.readAsBytesSync();
    File('${store.directory.path}/journal.json').writeAsStringSync('{partial');
    await expectLater(store.recover(), throwsFormatException);
    expect(store.current.readAsBytesSync(), before);
    expect(
      File('${store.directory.path}/journal.json').readAsStringSync(),
      '{partial',
    );
  });
  test(
    'held restore lock refuses another process without altering current',
    () async {
      await fixture(store.current, extraIncome: true);
      final before = store.current.readAsBytesSync();
      final lock = await File('${store.directory.path}/restore.lock')
          .open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      try {
        final result = await child('recovery', 'none');
        expect(result.exitCode, isNot(0));
        expect(store.current.readAsBytesSync(), before);
        expect(
          File('${store.directory.path}/journal.json').existsSync(),
          isFalse,
        );
      } finally {
        await lock.unlock();
        await lock.close();
      }
      await store.restore(backup.envelope, recoveryKey: backup.recoveryKey);
      await verifyRestored();
    },
  );
  test('hot stage sidecar fails closed rather than separating a database from its journal', () async {
    await fixture(store.current, extraIncome: true);
    final before = store.current.readAsBytesSync();
    File('${store.directory.path}/stage.db-journal')
        .writeAsStringSync('fixture');
    await expectLater(store.recover(), throwsStateError);
    expect(store.current.readAsBytesSync(), before);
    expect(
      File('${store.directory.path}/stage.db-journal').readAsStringSync(),
      'fixture',
    );
  });
  for (final sql in [
    'CREATE TABLE future_module (id TEXT)',
    'ALTER TABLE events ADD COLUMN hidden TEXT',
    'ALTER TABLE events ADD COLUMN derived INTEGER GENERATED ALWAYS AS (income-expense) VIRTUAL',
  ]) {
    test('capture refuses unknown persisted structure: $sql', () async {
      await fixture(store.current);
      final db = ProbeDatabase(store.current);
      try {
        await db.customStatement(sql);
        await expectLater(
          SnapshotCodec().capture(db),
          throwsA(isA<InvalidSnapshot>()),
        );
      } finally {
        await db.close();
      }
    });
  }
}

void safeDelete(Directory directory, Directory root) {
  if (!directory.resolveSymbolicLinksSync().startsWith(
    '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
  )) {
    throw StateError('Unsafe cleanup.');
  }
  directory.deleteSync(recursive: true);
}
