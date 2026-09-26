import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/restore_store.dart';
import 'package:validated_restore_probe/snapshot.dart';

const password = 'process-fixture-only-password';
List<int> randomKeyBytes() {
  final random = Random.secure();
  return List.generate(32, (_) => random.nextInt(256));
}

Future<void> seed(File target, StorageKey key, {bool extra = false}) async {
  target.parent.createSync(recursive: true);
  final raw = sqlite3.open(target.path);
  try {
    configureEncryption(raw, key);
    raw.execute(
      File('../modular_persistence/test/fixtures/v1.sql').readAsStringSync(),
    );
  } finally {
    raw.close();
  }
  final db = openEncrypted(target, key);
  try {
    await db.customSelect('SELECT * FROM accounts').get();
    if (extra) {
      final ws = WorkspaceId.parse('019f0000-0000-7000-8000-000000000000');
      final account = PostingAccount(
        id: PublicId.parse('019f0000-0000-7000-8000-000000000001'),
        workspace: ws,
        currency: Currency('USD', 2),
        expectedVersion: 1,
      );
      await FinancialWorkflows(db).post(
        Posting.income(
          id: PublicId.generate(),
          operation: OperationKey(ws, OperationId(PublicId.generate())),
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
  final root = Directory('.dart_tool/process-restore-tests')
    ..createSync(recursive: true);
  late CreatedBackup backup;
  late List<int> snapshot;
  late Directory work;
  late Directory owned;
  late File current;
  late File envelopeFile;
  late File credentialFile;
  late File keyFile;
  late File expectedFile;
  setUpAll(() async {
    final source = root.createTempSync('source-');
    try {
      final file = File('${source.path}/source.db');
      final sourceKey =
          StorageKey.random(); // Never persisted or supplied to children.
      await seed(file, sourceKey);
      final db = openEncrypted(file, sourceKey);
      try {
        snapshot = await SnapshotCodec().capture(db);
        backup = await RestoreStore(source).backup(db, password);
      } finally {
        await db.close();
      }
    } finally {
      safeDelete(source, root);
    }
    // Source database is gone before any restore child starts.
  });
  setUp(() {
    work = root.createTempSync('case-');
    owned = Directory('${work.path}/owned');
    current = File('${owned.path}/current.db');
    envelopeFile = File('${work.path}/envelope.json')
      ..writeAsStringSync(backup.envelope);
    credentialFile = File('${work.path}/credential.txt');
    keyFile = File('${work.path}/destination-key.bin')
      ..writeAsBytesSync(randomKeyBytes());
    expectedFile = File('${work.path}/expected.json')
      ..writeAsBytesSync(snapshot);
  });
  tearDown(() => safeDelete(work, root));
  Future<ProcessResult> run(List<String> args) async {
    final binary = File(
      '.dart_tool/worker/bundle/bin/restore_worker${Platform.isWindows ? '.exe' : ''}',
    );
    if (!binary.existsSync())
      throw StateError('Build encrypted restore_worker first.');
    return Process.run(
      binary.absolute.path,
      args,
      workingDirectory: work.absolute.path,
    );
  }

  Future<ProcessResult> restore({
    String mode = 'recovery',
    String checkpoint = 'none',
    String? credential,
  }) {
    credentialFile.writeAsStringSync(
      credential ?? (mode == 'password' ? password : backup.recoveryKey),
    );
    return run([
      'restore',
      owned.absolute.path,
      envelopeFile.absolute.path,
      credentialFile.absolute.path,
      mode,
      keyFile.absolute.path,
      checkpoint,
    ]);
  }

  Future<void> recover() async {
    final result = await run(['recover', owned.absolute.path]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  Future<void> verify() async {
    final result = await run([
      'verify',
      owned.absolute.path,
      keyFile.absolute.path,
      expectedFile.absolute.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout.toString().trim(), 'verified');
    for (final file in owned.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.db'),
    )) {
      final text = latin1.decode(file.readAsBytesSync());
      expect(text.startsWith('SQLite format 3'), isFalse);
      expect(text, isNot(contains('Frozen fixture')));
    }
  }

  for (final mode in ['password', 'recovery']) {
    test(
      'fresh encrypted restore and verification processes use only $mode and a new destination key',
      () async {
        final result = await restore(mode: mode);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        await verify();
      },
    );
  }
  for (final point in ['prepared', 'oldMoved', 'newMoved']) {
    test(
      'encrypted process exit at $point recovers original bytes usable with the retained old key',
      () async {
        final oldKey = StorageKey.random();
        await seed(current, oldKey, extra: true);
        final before = current.readAsBytesSync();
        final result = await restore(checkpoint: point);
        expect(
          result.exitCode,
          73,
          reason: '${result.stdout}\n${result.stderr}',
        );
        await recover();
        await recover();
        expect(current.readAsBytesSync(), before);
        final old = openEncrypted(current, oldKey);
        try {
          await SnapshotCodec().validate(old);
          expect(
            (await old
                    .customSelect('SELECT SUM(amount) AS n FROM legs')
                    .getSingle())
                .read<int>('n'),
            12200,
          );
        } finally {
          await old.close();
        }
        expect((await restore()).exitCode, 0);
        await verify();
      },
    );
  }
  test('first encrypted restore interrupted after new file move recovers to no current database', () async {
    expect((await restore(checkpoint: 'newMoved')).exitCode, 73);
    await recover();
    expect(current.existsSync(), isFalse);
    final preserved = owned
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList();
    expect(preserved, hasLength(1));
    expect(
      latin1.decode(preserved.single.readAsBytesSync()),
      isNot(contains('Frozen fixture')),
    );
    expect((await restore()).exitCode, 0);
    await verify();
  });
  for (final invalid in ['password', 'recovery', 'schema', 'truncated']) {
    test(
      'child rejects invalid $invalid without changing existing encrypted data',
      () async {
        await seed(current, StorageKey.random(), extra: true);
        final before = current.readAsBytesSync();
        if (invalid == 'schema') {
          final rootJson = jsonDecode(utf8.decode(snapshot));
          rootJson['schema'] = 999;
          final future = await EnvelopeCodec().create(
            utf8.encode(jsonEncode(rootJson)),
            password: password,
          );
          envelopeFile.writeAsStringSync(future.envelope);
        } else if (invalid == 'truncated') {
          envelopeFile.writeAsStringSync(
            backup.envelope.substring(0, backup.envelope.length - 16),
          );
        }
        final result = await restore(
          mode: invalid == 'schema' || invalid == 'password'
              ? 'password'
              : 'recovery',
          credential: invalid == 'password' || invalid == 'recovery'
              ? 'incorrect-fixture-credential'
              : null,
        );
        expect(result.exitCode, isNot(0));
        expect(result.exitCode, isNot(73));
        expect(current.readAsBytesSync(), before);
        expect(File('${owned.path}/journal.json').existsSync(), isFalse);
      },
    );
  }
}

void safeDelete(Directory directory, Directory root) {
  if (!directory.resolveSymbolicLinksSync().startsWith(
    '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
  ))
    throw StateError('Unsafe cleanup.');
  directory.deleteSync(recursive: true);
}
