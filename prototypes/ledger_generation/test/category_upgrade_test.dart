import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:ledger_generation_probe/safety_backup.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:storage_generation_probe/lock_wait.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

const password = 'synthetic-category-upgrade-only';
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
String digest(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  final root = Directory('.dart_tool/category-upgrade-tests')
    ..createSync(recursive: true);
  late CreatedBackup initial;
  late Directory work, backups;
  late FixtureKeySlots slots;
  late LedgerStore oldStore, store;
  late GenerationReceipt original;
  late UpgradeRequest request;
  late List<int> before, after;
  final unavailable = throwsA(isA<GenerationUnavailable>());

  LedgerStore reopen({bool categories = true}) => LedgerStore(
    Directory('${work.path}/store'),
    slots,
    catalogProtection: fixtureCatalogProtection(slots),
    categoryAware: categories,
  );
  File backupFile([UpgradeRequest? identity]) =>
      File('${backups.path}/${(identity ?? request).backupId.value}.envelope');
  Future<UpgradeReceipt> upgrade({void Function(String)? checkpoint}) =>
      upgradeCategories(
        store,
        request,
        backups,
        password: password,
        recoveryKey: initial.recoveryKey,
        checkpoint: checkpoint,
      );
  Future<T> catalog<T>(T Function(Database) read) async {
    final raw = sqlite3.open('${work.path}/store/catalog.db');
    try {
      configureEncryption(
        raw,
        await fixtureCatalogProtection(slots).loadKey(true),
      );
      return read(raw);
    } finally {
      raw.close();
    }
  }

  Future<int> physicalVersion(GenerationReceipt receipt) async {
    final raw = sqlite3.open(
      store.generations.databaseFile(receipt.generation).path,
    );
    try {
      configureEncryption(raw, await slots.read(receipt.slot));
      return raw.userVersion;
    } finally {
      raw.close();
    }
  }

  Future<T> categoryDatabase<T>(Future<T> Function(CategoriesAdapter) use) =>
      store.generations.withCurrent((file, key, receipt) async {
        final db = openEncrypted(
          file,
          key,
          categoryAware: true,
          storageBinding: StorageBinding(
            receipt.generation,
            receipt.slot,
            receipt.operation,
            receipt.fingerprint,
          ),
        );
        try {
          return await use(CategoriesAdapter(db));
        } finally {
          await db.close();
        }
      });
  Future<void> verifyBackup() async {
    final saved = await backupFile().readAsString();
    expect(await EnvelopeCodec().openWithPassword(saved, password), before);
    expect(
      await EnvelopeCodec().openWithRecovery(saved, initial.recoveryKey),
      before,
    );
  }

  Future<void> sourceIntact() async {
    expect(await physicalVersion(original), 3);
    final saved = await LedgerPayload().inspect(
      store.generations.databaseFile(original.generation),
      await slots.read(original.slot),
      original,
    );
    expect(utf8.encode(saved), before);
  }

  Future<ProcessResult> childUpgrade(String point) async {
    final input = File('${work.path}/request.json')
      ..writeAsStringSync(request.encode());
    final credentials = File('${work.path}/credentials.json')
      ..writeAsStringSync(
        jsonEncode({'password': password, 'recoveryKey': initial.recoveryKey}),
      );
    final executable = File(
      '.dart_tool/worker/bundle/bin/ledger_worker${Platform.isWindows ? '.exe' : ''}',
    );
    return Process.run(executable.absolute.path, [
      store.generations.directory.absolute.path,
      slots.directory.absolute.path,
      input.absolute.path,
      credentials.absolute.path,
      backups.absolute.path,
      'upgrade',
      point,
      '${work.absolute.path}/upgraded.json',
      'categories',
    ]);
  }

  void removeFixture(Directory directory) {
    if (!directory.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe fixture cleanup');
    directory.deleteSync(recursive: true);
  }

  setUpAll(() async {
    final fixture = root.createTempSync('seed-');
    final file = File('${fixture.path}/v1.db');
    final raw = sqlite3.open(file.path);
    raw.execute(
      File('../modular_persistence/test/fixtures/v1.sql').readAsStringSync(),
    );
    raw.close();
    final db = ProbeDatabase(file);
    try {
      initial = await EnvelopeCodec().create(
        await SnapshotCodec().capture(db),
        password: password,
      );
    } finally {
      await db.close();
      removeFixture(fixture);
    }
  });
  setUp(() async {
    work = root.createTempSync('case-');
    backups = Directory('${work.path}/backups')..createSync();
    slots = FixtureKeySlots(Directory('${work.path}/keys'));
    oldStore = reopen(categories: false);
    original = await oldStore.restore(
      initial.envelope,
      operation(),
      password: password,
    );
    before = await oldStore.snapshot();
    after = SnapshotCodec(categoryAware: true).canonicalize(before);
    store = reopen();
    request = await planCategoryUpgrade(
      store,
      operation(),
      PublicId.generate(),
    );
  });
  tearDown(() => removeFixture(work));

  test('new reader inspects schema 3 without migrating or allowing schema 4 writes', () async {
    expect(await store.snapshot(), before);
    await expectLater(store.post(income('5')), unavailable);
    expect(await catalog((db) => db.userVersion), 2);
    expect(
      await oldStore.balance(account),
      Money.parse(account.currency, '115'),
    );
    expect(backups.listSync(), isEmpty);
    await sourceIntact();
  });

  test('upgrade backs up live postings and retains old schema, receipts and balance', () async {
    final posting = income('8');
    await oldStore.post(posting);
    before = await oldStore.snapshot();
    after = SnapshotCodec(categoryAware: true).canonicalize(before);
    request = await planCategoryUpgrade(
      store,
      operation(),
      PublicId.generate(),
    );
    expect(request.sourceDigest, digest(before));
    expect(request.sourceDigest, isNot(original.fingerprint));
    final sourceFile = store.generations.databaseFile(original.generation);
    final sourceBytes = sourceFile.readAsBytesSync();
    final receipt = await upgrade();
    expect(receipt.backupDigest, digest(backupFile().readAsBytesSync()));
    expect(await catalog((db) => db.userVersion), 3);
    expect(await physicalVersion(receipt.target), 4);
    expect(await reopen().snapshot(), after);
    expect(await store.balance(account), Money.parse(account.currency, '123'));
    expect((await store.post(posting)).replayed, isTrue);
    expect(await store.snapshot(), after);
    await verifyBackup();
    await sourceIntact();
    expect(sourceFile.readAsBytesSync(), sourceBytes);
    await expectLater(oldStore.snapshot(), unavailable);
    final categoryId = PublicId.generate();
    await categoryDatabase(
      (adapter) => adapter.mutate(
        OperationKey(workspace, operation()),
        CategoryMutation.create(categoryId, '餐飲', CategoryKind.expense),
      ),
    );
    expect(
      await categoryDatabase(
        (adapter) async => (await adapter.read(workspace)).get(categoryId).name,
      ),
      '餐飲',
    );
    expect(await store.balance(account), Money.parse(account.currency, '123'));
  });

  test(
    'live source changes invalidate plan before backup or new catalog DDL',
    () async {
      await oldStore.post(income('5'));
      await expectLater(
        upgrade(),
        throwsA(
          isA<GenerationUnavailable>().having(
            (e) => e.problem,
            'problem',
            GenerationProblem.operationConflict,
          ),
        ),
      );
      expect(backups.listSync(), isEmpty);
      expect(await catalog((db) => db.userVersion), 2);
      expect(
        await oldStore.balance(account),
        Money.parse(account.currency, '120'),
      );
    },
  );

  test(
    'unsupported route and disabled capability reject without artifacts',
    () async {
      final encoded = jsonDecode(request.encode()) as List;
      encoded[4] = 'unknown-upgrade';
      expect(
        () => upgradeCategories(
          store,
          UpgradeRequest.decode(jsonEncode(encoded)),
          backups,
          password: password,
          recoveryKey: initial.recoveryKey,
        ),
        throwsA(isA<InvalidSnapshot>()),
      );
      expect(
        () => upgradeCategories(
          oldStore,
          request,
          backups,
          password: password,
          recoveryKey: initial.recoveryKey,
        ),
        throwsA(isA<InvalidSnapshot>()),
      );
      expect(backups.listSync(), isEmpty);
      expect(await catalog((db) => db.userVersion), 2);
    },
  );

  test(
    'unknown physical source version fails before backup and stays unchanged',
    () async {
      final file = store.generations.databaseFile(original.generation);
      final raw = sqlite3.open(file.path);
      configureEncryption(raw, await slots.read(original.slot));
      raw.userVersion = 99;
      raw.close();
      final bytes = file.readAsBytesSync();
      await expectLater(upgrade(), unavailable);
      expect(backups.listSync(), isEmpty);
      expect(file.readAsBytesSync(), bytes);
    },
  );

  test(
    'invalid backup destination and credentials keep schema and keys unchanged',
    () async {
      final count = slots.directory.listSync().length;
      for (final destination in [
        store.generations.directory,
        Directory('${work.path}/missing'),
      ]) {
        await expectLater(
          upgradeCategories(
            store,
            request,
            destination,
            password: password,
            recoveryKey: initial.recoveryKey,
          ),
          unavailable,
        );
      }
      await expectLater(
        upgradeCategories(
          store,
          request,
          backups,
          password: 'short',
          recoveryKey: initial.recoveryKey,
        ),
        unavailable,
      );
      await expectLater(
        upgradeCategories(
          store,
          request,
          backups,
          password: password,
          recoveryKey: 'invalid-key',
        ),
        unavailable,
      );
      expect(backups.listSync(), isEmpty);
      expect(await catalog((db) => db.userVersion), 2);
      expect(slots.directory.listSync().length, count);
      await sourceIntact();
    },
  );

  test(
    'tampered persisted backup stops upgrade without overwriting artifact',
    () async {
      await expectLater(
        upgrade(
          checkpoint: (point) {
            if (point == 'backup:written')
              backupFile().writeAsStringSync('damaged-fixture', flush: true);
          },
        ),
        unavailable,
      );
      await expectLater(upgrade(), unavailable);
      expect(backupFile().readAsStringSync(), 'damaged-fixture');
      expect(await catalog((db) => db.userVersion), 2);
      await sourceIntact();
    },
  );

  test('retry requires both original credentials and reuses exact persisted envelope', () async {
    await expectLater(
      upgrade(
        checkpoint: (point) {
          if (point == 'backup:written')
            throw StateError('simulate reply loss');
        },
      ),
      unavailable,
    );
    final saved = backupFile().readAsBytesSync();
    for (final wrongPassword in [true, false]) {
      await expectLater(
        upgradeCategories(
          store,
          request,
          backups,
          password: wrongPassword ? 'another-valid-password' : password,
          recoveryKey: wrongPassword ? initial.recoveryKey : 'invalid-key',
        ),
        unavailable,
      );
      expect(backupFile().readAsBytesSync(), saved);
      expect(await catalog((db) => db.userVersion), 2);
    }
    final receipt = await upgrade();
    expect(backupFile().readAsBytesSync(), saved);
    expect(receipt.backupDigest, digest(saved));
    expect(await store.snapshot(), after);
  });

  test(
    'completed retry does not reconvert or replace later financial data',
    () async {
      final first = await upgrade();
      await store.post(income('5'));
      final later = await store.snapshot();
      final replacement = await store.backup(password);
      final active = await store.restore(
        replacement.envelope,
        operation(),
        password: password,
      );
      final again = await upgrade();
      expect(again.target.generation, first.target.generation);
      expect(
        (await store.generations.current())!.receipt.generation,
        active.generation,
      );
      expect(await store.snapshot(), later);
      expect(
        await store.balance(account),
        Money.parse(account.currency, '120'),
      );
    },
  );

  test('cancelled wait creates no backup and leaves source readable', () async {
    await expectLater(
      upgradeCategories(
        store,
        request,
        backups,
        password: password,
        recoveryKey: initial.recoveryKey,
        cancellation: LockWaitCancellation()..cancel(),
      ),
      unavailable,
    );
    expect(backups.listSync(), isEmpty);
    expect(await oldStore.snapshot(), before);
  });

  for (final point in [
    'backup:created',
    'backup:written',
    'backup:verified',
    'upgradeCatalogWriting',
    'reserved',
    'table:events',
    'table:categories',
    'table:category_changes',
    'validated',
    'publishing',
    'published',
  ]) {
    test(
      'independent process exit at $point keeps a complete Ledger and safe retry',
      () async {
        final child = await childUpgrade(point);
        expect(child.exitCode, 73, reason: child.stderr.toString());
        final published = point == 'published';
        expect(await reopen().snapshot(), published ? after : before);
        await sourceIntact();
        final saved = backupFile().readAsBytesSync();
        if (point == 'backup:created') {
          expect(saved, isEmpty);
          await expectLater(upgrade(), unavailable);
          expect(backupFile().readAsBytesSync(), saved);
          request = await planCategoryUpgrade(
            store,
            operation(),
            PublicId.generate(),
          );
        } else {
          await verifyBackup();
        }
        if (point.startsWith('backup:') || point == 'upgradeCatalogWriting') {
          expect(await catalog((db) => db.userVersion), 2);
        }
        final retried = await childUpgrade('none');
        expect(retried.exitCode, 0, reason: retried.stderr.toString());
        expect(await reopen().snapshot(), after);
        expect(
          await store.balance(account),
          Money.parse(account.currency, '115'),
        );
        if (point != 'backup:created')
          expect(backupFile().readAsBytesSync(), saved);
        expect(
          await catalog(
            (db) => db.select(
              "SELECT count(*) AS n FROM attempts WHERE operation=? AND status='committed'",
              [request.operation.toString()],
            ).single['n'],
          ),
          1,
        );
        await sourceIntact();
      },
    );
  }

  test(
    'same plaintext in a different envelope conflicts after intent is recorded',
    () async {
      await expectLater(
        upgrade(
          checkpoint: (point) {
            if (point == 'reserved') throw StateError('stop after intent');
          },
        ),
        unavailable,
      );
      final different = await EnvelopeCodec().create(
        before,
        password: password,
        recoveryKey: initial.recoveryKey,
      );
      backupFile().writeAsStringSync(different.envelope, flush: true);
      await expectLater(
        upgrade(),
        throwsA(
          isA<GenerationUnavailable>().having(
            (e) => e.problem,
            'problem',
            GenerationProblem.operationConflict,
          ),
        ),
      );
      expect(await store.snapshot(), before);
      expect(backupFile().readAsStringSync(), different.envelope);
      await sourceIntact();
    },
  );

  test(
    'different source in an existing valid envelope is not reused',
    () async {
      backupFile().writeAsStringSync(initial.envelope, flush: true);
      await expectLater(upgrade(), unavailable);
      expect(await catalog((db) => db.userVersion), 2);
      expect(backupFile().readAsStringSync(), initial.envelope);
      await sourceIntact();
    },
  );

  test('new backup readback rejects changed raw bytes even if UTF-8 decodes equally', () async {
    await expectLater(
      upgrade(
        checkpoint: (point) {
          if (point == 'backup:written') {
            final bytes = backupFile().readAsBytesSync();
            backupFile().writeAsBytesSync([
              0xef,
              0xbb,
              0xbf,
              ...bytes,
            ], flush: true);
          }
        },
      ),
      unavailable,
    );
    expect(await catalog((db) => db.userVersion), 2);
    final saved = backupFile().readAsBytesSync();
    // A later retry may validate this existing envelope, but must record its
    // actual file digest rather than a digest of the decoded string.
    final receipt = await upgrade();
    expect(receipt.backupDigest, digest(saved));
    expect(backupFile().readAsBytesSync(), saved);
    await verifyBackup();
  });

  test(
    'full 5000-event ledger upgrades without losing data or replay protection',
    () async {
      final watch = Stopwatch()..start();
      var units = BigInt.from(11500);
      late Posting last;
      await oldStore.withSession((session) async {
        for (var i = 3; i < LedgerSession.maxEvents; i++) {
          final minorUnits = 1 + (i * 7919) % 10000;
          last = Posting.income(
            id: PublicId.generate(),
            operation: OperationKey(workspace, operation()),
            date: BusinessDate(2026, 9, 26),
            account: account,
            amount: Money(account.currency, BigInt.from(minorUnits)),
          );
          expect((await session.post(last)).replayed, isFalse);
          expect((await session.post(last)).replayed, isTrue);
          units += BigInt.from(minorUnits);
        }
      });
      final writesMs = watch.elapsedMilliseconds;
      before = await oldStore.snapshot();
      after = SnapshotCodec(categoryAware: true).canonicalize(before);
      request = await planCategoryUpgrade(
        store,
        operation(),
        PublicId.generate(),
      );
      final startedUpgrade = watch.elapsedMilliseconds;
      final receipt = await upgrade();
      final upgradeMs = watch.elapsedMilliseconds - startedUpgrade;
      expect(await store.snapshot(), after);
      await verifyBackup();
      await sourceIntact();
      expect(await reopen().balance(account), Money(account.currency, units));
      await store.withSession((session) async {
        expect((await session.post(last)).replayed, isTrue);
        await expectLater(
          session.post(income('1')),
          throwsA(isA<PreviewCapacity>()),
        );
      });
      final firstGeneration = receipt.target.generation;
      expect((await upgrade()).target.generation, firstGeneration);
      expect(await store.snapshot(), after);
      final newBackup = await store.backup(
        password,
        recoveryKey: initial.recoveryKey,
      );
      for (final recovery in [false, true]) {
        final targetKeys = FixtureKeySlots(
          Directory('${work.path}/scale-keys-$recovery'),
        );
        final target = LedgerStore(
          Directory('${work.path}/scale-target-$recovery'),
          targetKeys,
          catalogProtection: fixtureCatalogProtection(targetKeys),
          categoryAware: true,
        );
        await target.restore(
          newBackup.envelope,
          operation(),
          password: recovery ? null : password,
          recoveryKey: recovery ? initial.recoveryKey : null,
        );
        expect(await target.snapshot(), after);
        expect(await target.balance(account), Money(account.currency, units));
        expect((await target.post(last)).replayed, isTrue);
      }
      File('.dart_tool/category-upgrade-scale-result.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'recordedUtc': DateTime.now().toUtc().toIso8601String(),
          'platform': Platform.operatingSystemVersion,
          'dart': Platform.version,
          'events': 5000,
          'newPostings': 4997,
          'postingRetries': 4997,
          'sourceSnapshotBytes': before.length,
          'targetSnapshotBytes': after.length,
          'sourceDigest': digest(before),
          'targetDigest': digest(after),
          'writesMs': writesMs,
          'upgradeMs': upgradeMs,
          'totalMs': watch.elapsedMilliseconds,
          'fullDataEquality': true,
          'balancePreserved': true,
          'retryIdempotent': true,
          'sourceRetained': true,
          'bothBackupCredentialsVerified': true,
          'bothRestoreRoutesVerified': true,
          'capacityGuardPreserved': true,
          'deviceTested': false,
        }),
        flush: true,
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  test(
    'planning a missing source does not initialize catalog or keys',
    () async {
      final emptyDirectory = Directory('${work.path}/missing-source');
      final emptyKeys = FixtureKeySlots(Directory('${work.path}/missing-keys'));
      final empty = LedgerStore(
        emptyDirectory,
        emptyKeys,
        catalogProtection: fixtureCatalogProtection(emptyKeys),
        categoryAware: true,
      );
      await expectLater(
        planCategoryUpgrade(empty, operation(), PublicId.generate()),
        unavailable,
      );
      expect(File('${emptyDirectory.path}/catalog.db').existsSync(), isFalse);
      expect(
        File('${emptyDirectory.path}/catalog.init.db').existsSync(),
        isFalse,
      );
      expect(
        emptyKeys.directory.existsSync() ? emptyKeys.directory.listSync() : [],
        isEmpty,
      );
    },
  );

  for (final upgradedBackup in [false, true]) {
    for (final mode in ['password', 'recovery']) {
      test(
        '${upgradedBackup ? 'schema 4' : 'safety schema 3'} restores by $mode without source DB or keys',
        () async {
          await upgrade();
          late File input;
          late List<int> expected;
          PublicId? categoryId;
          if (upgradedBackup) {
            categoryId = PublicId.generate();
            await categoryDatabase(
              (adapter) => adapter.mutate(
                OperationKey(workspace, operation()),
                CategoryMutation.create(
                  categoryId!,
                  '保留分類',
                  CategoryKind.expense,
                ),
              ),
            );
            expected = await store.snapshot();
            final backup = await store.backup(
              password,
              recoveryKey: initial.recoveryKey,
            );
            input = File('${backups.path}/after.envelope')
              ..writeAsStringSync(backup.envelope);
          } else {
            expected = before;
            input = backupFile();
          }
          removeFixture(store.generations.directory);
          removeFixture(slots.directory);
          final credential = File('${work.path}/single-credential.txt')
            ..writeAsStringSync(
              mode == 'password' ? password : initial.recoveryKey,
            );
          final output = File('${work.path}/restored.json');
          final target = Directory('${work.path}/fresh-target');
          final newKeys = FixtureKeySlots(Directory('${work.path}/fresh-keys'));
          final executable = File(
            '.dart_tool/worker/bundle/bin/ledger_worker${Platform.isWindows ? '.exe' : ''}',
          );
          final result = await Process.run(executable.absolute.path, [
            target.absolute.path,
            newKeys.directory.absolute.path,
            input.absolute.path,
            credential.absolute.path,
            operation().toString(),
            mode,
            'none',
            output.absolute.path,
            upgradedBackup ? 'categories' : 'protected',
          ]);
          expect(result.exitCode, 0, reason: result.stderr.toString());
          expect(output.readAsBytesSync(), expected);
          store = LedgerStore(
            target,
            newKeys,
            catalogProtection: fixtureCatalogProtection(newKeys),
            categoryAware: upgradedBackup,
          );
          expect(
            await store.balance(account),
            Money.parse(account.currency, '115'),
          );
          final replay = await store.post(
            income(
              '20',
              op: OperationId.parse('019f0000-0000-7000-8000-000000000011'),
            ),
          );
          expect(replay.replayed, isTrue);
          expect(await store.snapshot(), expected);
          if (categoryId != null) {
            expect(
              await categoryDatabase(
                (adapter) async =>
                    (await adapter.read(workspace)).get(categoryId!).name,
              ),
              '保留分類',
            );
          }
        },
      );
    }
  }
}
