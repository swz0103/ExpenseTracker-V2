import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/operations.dart'
    show OperationConflict;
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:storage_generation_probe/lock_wait.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

const password = 'fixture-only-password-2026';
final workspace = WorkspaceId.parse('019f0000-0000-7000-8000-000000000000');
final account = PostingAccount(
  id: PublicId.parse('019f0000-0000-7000-8000-000000000001'),
  workspace: workspace,
  currency: Currency('USD', 2),
  expectedVersion: 1,
);
OperationId operation() => OperationId(PublicId.generate());
Posting income(String amount, {OperationId? op}) => Posting.income(
  id: PublicId.generate(),
  operation: OperationKey(workspace, op ?? operation()),
  date: BusinessDate(2026, 9, 26),
  account: account,
  amount: Money.parse(account.currency, amount),
);
StorageBinding binding() => StorageBinding(
  PublicId.generate(),
  PublicId.generate(),
  operation(),
  List.filled(64, 'a').join(),
);

void main() {
  final root = Directory('.dart_tool/ledger-tests')
    ..createSync(recursive: true);
  late Directory work;
  late LedgerStore store;
  late FixtureKeySlots keys;
  late List<int> source;
  late CreatedBackup backup;
  final codec = SnapshotCodec(generationAware: true);
  setUpAll(() async {
    final file = File('${root.path}/source.db');
    final raw = sqlite3.open(file.path);
    raw.execute(
      File('../modular_persistence/test/fixtures/v1.sql').readAsStringSync(),
    );
    raw.close();
    final db = ProbeDatabase(file);
    try {
      source = await SnapshotCodec().capture(db);
    } finally {
      await db.close();
    }
    backup = await EnvelopeCodec().create(source, password: password);
    file.deleteSync(); // No source database or source key exists for child restores.
  });
  setUp(() {
    work = root.createTempSync('case-');
    keys = FixtureKeySlots(Directory('${work.path}/keys'));
    store = LedgerStore(Directory('${work.path}/store'), keys);
  });
  tearDown(() {
    final base = root.absolute.path;
    final target = work.absolute.path;
    if (!target.startsWith('$base${Platform.pathSeparator}'))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  });
  Future<GenerationReceipt> install() =>
      store.restore(backup.envelope, operation(), password: password);
  Future<T> withRawGeneration<T>(T Function(Database) work) =>
      store.generations.withCurrent((file, key, receipt) async {
        final raw = sqlite3.open(file.path);
        try {
          configureEncryption(raw, key);
          return work(raw);
        } finally {
          raw.close();
        }
      });
  Future<ProcessResult> child(
    String mode,
    String point,
    OperationId op,
    CreatedBackup input, {
    bool protected = false,
  }) async {
    final envelope = File('${work.path}/backup.json')
      ..writeAsStringSync(input.envelope);
    final credential = File('${work.path}/credential.txt')
      ..writeAsStringSync(mode == 'password' ? password : input.recoveryKey);
    final exe = File(
      '.dart_tool/worker/bundle/bin/ledger_worker${Platform.isWindows ? '.exe' : ''}',
    );
    return Process.run(exe.absolute.path, [
      store.generations.directory.absolute.path,
      keys.directory.absolute.path,
      envelope.absolute.path,
      credential.absolute.path,
      op.toString(),
      mode,
      point,
      '${work.absolute.path}/result.json',
      if (protected) 'protected',
    ]);
  }

  test(
    'cancelled financial access preserves snapshot and posting can retry',
    () async {
      await install();
      final before = await store.snapshot();
      final cancellation = LockWaitCancellation()..cancel();
      final rejected = throwsA(
        isA<GenerationUnavailable>().having(
          (error) => error.problem,
          'problem',
          GenerationProblem.lockCancelled,
        ),
      );
      final posting = income('7');
      await expectLater(
        store.post(posting, cancellation: cancellation),
        rejected,
      );
      await expectLater(
        store.balance(account, cancellation: cancellation),
        rejected,
      );
      await expectLater(store.snapshot(cancellation: cancellation), rejected);
      await expectLater(
        store.backup(password, cancellation: cancellation),
        rejected,
      );
      expect(await store.snapshot(), before);
      expect((await store.post(posting)).replayed, isFalse);
      expect((await store.post(posting)).replayed, isTrue);
      expect((await store.balance(account)).minorUnits, BigInt.from(12200));
    },
  );

  test('capacity projection is transactional and rebuilds when untrusted', () async {
    await install();
    final committedOperation = operation();
    await store.withSession(
      (session) => session.post(income('1', op: committedOperation)),
    );
    final first = await withRawGeneration(
      (raw) => raw.select('SELECT * FROM capacity_projection').single,
    );
    expect(first['format_version'], 1);
    expect(first['schema_version'], 3);
    expect(first['generation'], isNotEmpty);
    expect(first['rows'], greaterThan(0));
    expect(first['bytes'], greaterThan(0));
    expect(first['checksum'], matches(RegExp(r'^[0-9a-f]{64}$')));
    final portable = jsonDecode(utf8.decode(await store.snapshot())) as Map;
    expect((portable['tables'] as Map), isNot(contains('capacity_projection')));

    // A clean shutdown normally flushes the latest projection once. A hard
    // process exit may instead leave an older, internally checksummed row;
    // actual authority counts must reject and rebuild it before use.
    final staleCounts = jsonDecode(first['table_counts'] as String) as Map;
    staleCounts['events'] = (staleCounts['events'] as int) - 1;
    final staleRows = (first['rows'] as int) - 1;
    final encodedStaleCounts = jsonEncode(staleCounts);
    final staleChecksum = sha256
        .convert(
          utf8.encode(
            '1|3|${first['generation']}|$staleRows|${first['bytes']}|$encodedStaleCounts',
          ),
        )
        .toString();
    await withRawGeneration<void>((raw) {
      raw.execute(
        'UPDATE capacity_projection SET rows=?,table_counts=?,checksum=? '
        'WHERE singleton=1',
        [staleRows, encodedStaleCounts, staleChecksum],
      );
    });
    await store.withSession((session) => session.accounts(workspace));
    final afterStale = await withRawGeneration(
      (raw) => raw.select('SELECT * FROM capacity_projection').single,
    );
    expect(afterStale['rows'], first['rows']);
    expect(afterStale['table_counts'], first['table_counts']);
    expect(afterStale['checksum'], first['checksum']);

    await expectLater(
      store.withSession(
        (session) => session.post(income('99', op: committedOperation)),
      ),
      throwsA(isA<OperationConflict>()),
    );
    final afterFailure = await withRawGeneration(
      (raw) => raw.select('SELECT * FROM capacity_projection').single,
    );
    expect(afterFailure['rows'], first['rows']);
    expect(afterFailure['bytes'], first['bytes']);
    expect(afterFailure['table_counts'], first['table_counts']);
    expect(afterFailure['checksum'], first['checksum']);

    await withRawGeneration<void>((raw) {
      raw.execute(
        'UPDATE capacity_projection SET checksum=? WHERE singleton=1',
        [List.filled(64, '0').join()],
      );
    });
    await store.withSession((session) => session.post(income('2')));
    final rebuilt = await withRawGeneration(
      (raw) => raw.select('SELECT * FROM capacity_projection').single,
    );
    expect(rebuilt['checksum'], isNot(List.filled(64, '0').join()));
    final counts = jsonDecode(rebuilt['table_counts'] as String) as Map;
    expect(
      counts.values.cast<int>().fold<int>(0, (sum, value) => sum + value),
      rebuilt['rows'],
    );

    final foreignGeneration = PublicId.generate().value;
    await withRawGeneration<void>((raw) {
      raw.execute(
        'UPDATE capacity_projection SET generation=? WHERE singleton=1',
        [foreignGeneration],
      );
    });
    await store.withSession((session) => session.accounts(workspace));
    final rebound = await withRawGeneration(
      (raw) => raw.select('SELECT * FROM capacity_projection').single,
    );
    expect(rebound['generation'], rebuilt['generation']);
    expect(rebound['generation'], isNot(foreignGeneration));

    await withRawGeneration<void>(
      (raw) => raw.execute('DROP TABLE capacity_projection'),
    );
    await store.withSession((session) => session.post(income('3')));
    final recreated = await withRawGeneration(
      (raw) => raw.select('SELECT * FROM capacity_projection').single,
    );
    expect(recreated['rows'], greaterThan(rebuilt['rows'] as int));
  });

  test(
    'cancelled restore creates no target and same operation can retry',
    () async {
      final op = operation();
      await expectLater(
        store.restore(
          backup.envelope,
          op,
          password: password,
          cancellation: LockWaitCancellation()..cancel(),
        ),
        throwsA(
          isA<GenerationUnavailable>().having(
            (error) => error.problem,
            'problem',
            GenerationProblem.lockCancelled,
          ),
        ),
      );
      expect(store.generations.directory.existsSync(), isFalse);
      expect(keys.directory.existsSync(), isFalse);
      await store.restore(backup.envelope, op, password: password);
      expect(await store.snapshot(), codec.canonicalize(source));
    },
  );

  for (final mode in ['password', 'recovery']) {
    for (final point in [
      'catalogWriting',
      'catalogPublishing',
      'catalogPublished',
    ]) {
      test(
        'clean $mode restore resumes interrupted initialization at $point',
        () async {
          store = LedgerStore(
            Directory('${work.path}/store'),
            keys,
            catalogProtection: fixtureCatalogProtection(keys),
          );
          final op = operation();
          expect(
            (await child(mode, point, op, backup, protected: true)).exitCode,
            73,
          );
          final controlKeys = {
            for (final file in keys.directory.listSync().whereType<File>())
              file.path: file.readAsBytesSync(),
          };
          expect(controlKeys.length, 1);
          expect(
            store.generations.directory.listSync().where(
              (file) => file.path.contains('gen-'),
            ),
            isEmpty,
          );
          expect(
            (await child(mode, 'none', op, backup, protected: true)).exitCode,
            0,
          );
          expect(await store.snapshot(), codec.canonicalize(source));
          for (final entry in controlKeys.entries) {
            expect(File(entry.key).readAsBytesSync(), entry.value);
          }
          final active = (await store.generations.current())!.receipt;
          expect(
            (await child(mode, 'none', op, backup, protected: true)).exitCode,
            0,
          );
          expect(
            (await store.generations.current())!.receipt.generation,
            active.generation,
          );
          expect((await store.balance(account)).minorUnits, BigInt.from(11500));
        },
      );
    }
    test(
      'protected catalog supports clean $mode restore and later writes',
      () async {
        final protection = fixtureCatalogProtection(keys);
        store = LedgerStore(
          Directory('${work.path}/store'),
          keys,
          catalogProtection: protection,
        );
        final result = await child(
          mode,
          'none',
          operation(),
          backup,
          protected: true,
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(await store.snapshot(), codec.canonicalize(source));
        final posting = income('7');
        await store.post(posting);
        final expected = await store.snapshot();
        expect(
          utf8.decode(expected),
          isNot(contains(protection.identity.value)),
        );
        final portable = await store.backup(password);
        final restored = await child(
          mode,
          'none',
          operation(),
          portable,
          protected: true,
        );
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
        expect(await store.snapshot(), expected);
        expect((await store.post(posting)).replayed, isTrue);
        expect((await store.balance(account)).minorUnits, BigInt.from(12200));
        final active = (await store.generations.current())!;
        final raw = latin1.decode(
          File('${work.path}/store/catalog.db').readAsBytesSync(),
        );
        expect(raw, isNot(startsWith('SQLite format 3')));
        expect(raw, isNot(contains(active.receipt.fingerprint)));
      },
    );
  }

  test(
    'legacy restore preserves every financial row, balance and receipt',
    () async {
      final receipt = await install();
      expect(await store.snapshot(), codec.canonicalize(source));
      expect((await store.balance(account)).minorUnits, BigInt.from(11500));
      final replay = await store.post(
        income(
          '20',
          op: OperationId.parse('019f0000-0000-7000-8000-000000000011'),
        ),
      );
      expect(replay.replayed, isTrue);
      expect(await store.snapshot(), codec.canonicalize(source));
      final text = utf8.decode(await store.snapshot());
      expect(text, isNot(contains(receipt.slot.value)));
      expect(text, isNot(contains(receipt.generation.value)));
      expect(text, isNot(contains(receipt.fingerprint)));
      expect(
        () => SnapshotCodec().canonicalize(utf8.encode(text)),
        throwsA(isA<InvalidSnapshot>()),
      );
    },
  );

  test('live posting, installation retry and next portable restore retain new entries', () async {
    final op = operation();
    final receipt = await store.restore(
      backup.envelope,
      op,
      password: password,
    );
    final posting = income('7');
    expect((await store.post(posting)).replayed, isFalse);
    final current = await store.snapshot();
    expect(
      (await store.restore(backup.envelope, op, password: password)).generation,
      receipt.generation,
    );
    expect(await store.snapshot(), current);
    final next = await store.backup(password);
    final other = LedgerStore(
      Directory('${work.path}/other'),
      FixtureKeySlots(Directory('${work.path}/other-keys')),
    );
    final restored = await other.restore(
      next.envelope,
      operation(),
      recoveryKey: next.recoveryKey,
    );
    expect(restored.slot, isNot(receipt.slot));
    expect(await other.snapshot(), current);
    expect((await other.post(posting)).replayed, isTrue);
    expect((await other.balance(account)).minorUnits, BigInt.from(12200));
  });

  for (final mode in ['password', 'recovery']) {
    test('clean process restores with $mode alone', () async {
      final result = await child(mode, 'none', operation(), backup);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        File('${work.path}/result.json').readAsBytesSync(),
        codec.canonicalize(source),
      );
      expect(await store.snapshot(), codec.canonicalize(source));
    });
  }

  for (final point in [
    'reserved',
    'keySaved',
    'table:accounts',
    'staged',
    'validated',
    'publishing',
    'published',
  ]) {
    test(
      'Ledger process interruption at $point keeps coherent active data',
      () async {
        final old = await install();
        await store.post(income('7'));
        final oldData = await store.snapshot();
        final op = operation();
        expect((await child('recovery', point, op, backup)).exitCode, 73);
        final current = await store.generations.current();
        expect(
          current!.receipt.generation == old.generation,
          point != 'published',
        );
        expect(
          await store.snapshot(),
          point == 'published' ? codec.canonicalize(source) : oldData,
        );
        await store.restore(
          backup.envelope,
          op,
          recoveryKey: backup.recoveryKey,
        );
        expect(await store.snapshot(), codec.canonicalize(source));
        expect(
          await store.generations.databaseFile(old.generation).exists(),
          isTrue,
        );
        await keys.read(old.slot);
      },
    );
  }

  for (final change in ['manifest', 'identity', 'column', 'finance']) {
    test(
      'rejects $change in portable backup without changing active data',
      () async {
        await install();
        final original = await store.snapshot();
        final doc = jsonDecode(utf8.decode(original)) as Map<String, dynamic>;
        switch (change) {
          case 'manifest':
            (doc['modules'] as Map)['future'] = 1;
          case 'identity':
            (doc['tables'] as Map)['storage_identity'] = [];
          case 'column':
            (doc['tables']['events'][0] as Map)['future'] = 'x';
          case 'finance':
            doc['tables']['legs'][0]['amount'] = '999';
        }
        final invalid = await EnvelopeCodec().create(
          utf8.encode(jsonEncode(doc)),
          password: password,
        );
        await expectLater(
          store.restore(
            invalid.envelope,
            operation(),
            recoveryKey: invalid.recoveryKey,
          ),
          throwsA(anything),
        );
        expect(await store.snapshot(), original);
      },
    );
  }

  test('wrong password and wrong local binding preserve active file', () async {
    final receipt = await install();
    await expectLater(
      store.restore(
        backup.envelope,
        operation(),
        password: 'wrong-password-fixture',
      ),
      throwsA(isA<BackupException>()),
    );
    final file = store.generations.databaseFile(receipt.generation);
    final before = file.readAsBytesSync();
    final wrong = openEncrypted(
      file,
      await keys.read(receipt.slot),
      storageBinding: binding(),
    );
    try {
      await expectLater(
        wrong.customSelect('SELECT * FROM accounts').get(),
        throwsA(anything),
      );
    } finally {
      await wrong.close();
    }
    expect(file.readAsBytesSync(), before);
    expect(await store.snapshot(), codec.canonicalize(source));
  });

  test(
    'unknown persisted column is refused instead of excluded from backup',
    () async {
      final receipt = await install();
      final raw = sqlite3.open(
        store.generations.databaseFile(receipt.generation).path,
      );
      configureEncryption(raw, await keys.read(receipt.slot));
      raw.execute(
        "ALTER TABLE storage_identity ADD COLUMN future TEXT GENERATED ALWAYS AS ('x') VIRTUAL",
      );
      raw.close();
      await expectLater(
        store.snapshot(),
        throwsA(isA<GenerationUnavailable>()),
      );
    },
  );

  for (final version in [2, 99]) {
    test(
      'active schema $version refuses automatic migration or rewrite',
      () async {
        final receipt = await install();
        final file = store.generations.databaseFile(receipt.generation);
        final raw = sqlite3.open(file.path);
        configureEncryption(raw, await keys.read(receipt.slot));
        raw.execute('PRAGMA user_version=$version');
        raw.close();
        final before = file.readAsBytesSync();
        await expectLater(
          store.snapshot(),
          throwsA(isA<GenerationUnavailable>()),
        );
        expect(file.readAsBytesSync(), before);
      },
    );
  }

  test(
    'portable field order normalizes before publication comparison',
    () async {
      final doc = jsonDecode(utf8.decode(source)) as Map<String, dynamic>;
      final tables = doc['tables'] as Map;
      for (final rows in tables.values) {
        for (var i = 0; i < (rows as List).length; i++) {
          rows[i] = Map.fromEntries(
            (rows[i] as Map<String, dynamic>).entries.toList().reversed,
          );
        }
      }
      await store.generations.install(jsonEncode(doc), operation());
      expect(await store.snapshot(), codec.canonicalize(source));
    },
  );

  for (final mode in ['password', 'recovery']) {
    test('new portable version restores in clean process with $mode', () async {
      final owned = Directory('${work.path}/source-owned')..createSync();
      final sourceStore = LedgerStore(
        Directory('${owned.path}/db'),
        FixtureKeySlots(Directory('${owned.path}/keys')),
      );
      await sourceStore.restore(
        backup.envelope,
        operation(),
        password: password,
      );
      await sourceStore.post(income('7'));
      final expected = await sourceStore.snapshot();
      final portable = await sourceStore.backup(password);
      if (owned.absolute.parent.path != work.absolute.path)
        throw StateError('Unsafe cleanup');
      owned.deleteSync(recursive: true);
      final result = await child(mode, 'none', operation(), portable);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File('${work.path}/result.json').readAsBytesSync(), expected);
    });
  }

  test('encrypted schema 2 binding migration rolls back after failure and can retry', () async {
    final file = File('${work.path}/migration.db');
    final key = StorageKey.random();
    await SnapshotCodec().stage(
      source,
      file,
      openDatabase: (target) => openEncrypted(target, key),
    );
    final identity = binding();
    final broken = openEncrypted(
      file,
      key,
      storageBinding: identity,
      migrationCheckpoint: (point) {
        if (point == 'binding') throw StateError('fixture');
      },
    );
    try {
      await expectLater(
        broken.customSelect('SELECT * FROM accounts').get(),
        throwsA(anything),
      );
    } finally {
      await broken.close();
    }
    final old = openEncrypted(file, key);
    try {
      expect(await SnapshotCodec().capture(old), source);
    } finally {
      await old.close();
    }
    final next = openEncrypted(file, key, storageBinding: identity);
    try {
      expect(await codec.capture(next), codec.canonicalize(source));
    } finally {
      await next.close();
    }
  });
}
