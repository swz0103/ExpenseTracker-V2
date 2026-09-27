import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:test/test.dart';

String digest(String value) => sha256.convert(utf8.encode(value)).toString();

void main() {
  final root = Directory('.dart_tool/upgrade-tests')
    ..createSync(recursive: true);
  late Directory work;
  late FixtureKeySlots slots;
  late GenerationStore oldStore, store;
  late GenerationReceipt original;
  late UpgradeRequest request;
  OperationId op() => OperationId(PublicId.generate());
  GenerationStore reopen({bool aware = true}) => GenerationStore(
    Directory('${work.path}/store'),
    slots,
    catalogProtection: fixtureCatalogProtection(slots),
    upgradeAware: aware,
  );
  Future<T> inspectCatalog<T>(T Function(Database db) read) async {
    final db = sqlite3.open('${work.path}/store/catalog.db');
    try {
      configureEncryption(
        db,
        await fixtureCatalogProtection(slots).loadKey(true),
      );
      return read(db);
    } finally {
      db.close();
    }
  }

  PreparedUpgrade prepared() =>
      PreparedUpgrade('after', digest('synthetic-backup:before'));
  final conflict = throwsA(
    isA<GenerationUnavailable>().having(
      (e) => e.problem,
      'problem',
      GenerationProblem.operationConflict,
    ),
  );
  final unavailable = throwsA(isA<GenerationUnavailable>());
  setUp(() async {
    work = root.createTempSync('case-');
    slots = FixtureKeySlots(Directory('${work.path}/store-keys'));
    oldStore = reopen(aware: false);
    original = await oldStore.install('before', op());
    store = reopen();
    request = UpgradeRequest(
      operation: op(),
      sourceGeneration: original.generation,
      sourceDigest: digest('before'),
      route: 'fixture-1-to-2-v1',
      fromVersion: 1,
      toVersion: 2,
      backupId: PublicId.generate(),
    );
  });
  tearDown(() {
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  });

  test('preparation precedes all new DDL; upgrade and active reference commit together', () async {
    var called = false;
    final receipt = await store.upgrade(request, (source) async {
      expect(await inspectCatalog((db) => db.userVersion), 2);
      expect(source.receipt.generation, original.generation);
      expect(source.value, 'before');
      called = true;
      return prepared();
    });
    expect(called, isTrue);
    expect(receipt.backupDigest, prepared().backupDigest);
    expect(receipt.request.encode(), request.encode());
    expect((await reopen().current())!.value, 'after');
    expect(await inspectCatalog((db) => db.userVersion), 3);
    expect(
      await inspectCatalog(
        (db) => db.select("SELECT status FROM attempts WHERE operation=?", [
          request.operation.toString(),
        ]).single['status'],
      ),
      'committed',
    );
    expect(oldStore.databaseFile(original.generation).existsSync(), isTrue);
    await slots.read(original.slot);
    await expectLater(oldStore.current(), unavailable);
  });

  test(
    'failed preparation leaves catalog version, source and key slots unchanged',
    () async {
      final before = File('${work.path}/store/catalog.db').readAsBytesSync();
      final count = slots.directory.listSync().length;
      await expectLater(
        store.upgrade(request, (_) async => throw StateError('backup failed')),
        unavailable,
      );
      expect(File('${work.path}/store/catalog.db').readAsBytesSync(), before);
      expect(slots.directory.listSync().length, count);
      expect((await oldStore.current())!.value, 'before');
    },
  );

  test('committed retry skips preparation and cannot reactivate a retired generation', () async {
    final first = await store.upgrade(request, (_) async => prepared());
    final later = await store.install('later', op());
    final retry = await reopen().upgrade(
      request,
      (_) async => throw StateError('must not run'),
    );
    expect(retry.target.generation, first.target.generation);
    expect((await store.current())!.receipt.generation, later.generation);
  });

  test(
    'restore and upgrade operation IDs cannot alias in either direction',
    () async {
      final oldRequest = UpgradeRequest(
        operation: original.operation,
        sourceGeneration: original.generation,
        sourceDigest: request.sourceDigest,
        route: request.route,
        fromVersion: 1,
        toVersion: 2,
        backupId: request.backupId,
      );
      await expectLater(
        store.upgrade(oldRequest, (_) async => prepared()),
        conflict,
      );
      await store.upgrade(request, (_) async => prepared());
      await expectLater(store.install('after', request.operation), conflict);
    },
  );

  test(
    'source identity and live digest must match before preparation',
    () async {
      for (final changed in ['generation', 'digest']) {
        final bad = UpgradeRequest(
          operation: request.operation,
          sourceGeneration: changed == 'generation'
              ? PublicId.generate()
              : original.generation,
          sourceDigest: changed == 'digest'
              ? digest('changed')
              : request.sourceDigest,
          route: request.route,
          fromVersion: 1,
          toVersion: 2,
          backupId: request.backupId,
        );
        await expectLater(
          store.upgrade(bad, (_) async => throw StateError('must not run')),
          conflict,
        );
      }
      expect(await inspectCatalog((db) => db.userVersion), 2);
    },
  );

  test('same operation with changed route, versions, backup identity or source rejects', () async {
    await store.upgrade(request, (_) async => prepared());
    for (final index in [2, 3, 4, 5, 6, 7]) {
      final encoded = jsonDecode(request.encode()) as List;
      encoded[index] = switch (index) {
        2 || 7 => PublicId.generate().value,
        3 => digest('different'),
        4 => 'another-route',
        5 => 2,
        _ => 3,
      };
      if (index == 5) encoded[6] = 3;
      await expectLater(
        store.upgrade(
          UpgradeRequest.decode(jsonEncode(encoded)),
          (_) async => throw StateError('must not run'),
        ),
        conflict,
      );
    }
  });

  for (final point in [
    'upgradeCatalogWriting',
    'upgradeRecording',
    'upgradePrepared',
    'reserved',
    'keySaved',
    'databaseWriting',
    'staged',
    'validated',
    'publishing',
    'published',
  ]) {
    test(
      'process interruption at $point preserves a complete active generation and safe retry',
      () async {
        final input = File('${work.path}/request.json')
          ..writeAsStringSync(request.encode());
        final worker = File(
          '.dart_tool/worker/bundle/bin/generation_worker${Platform.isWindows ? '.exe' : ''}',
        ).absolute.path;
        final result = await Process.run(worker, [
          'upgrade',
          store.directory.absolute.path,
          input.absolute.path,
          'after',
          point,
          'protected-upgrades',
        ]);
        expect(result.exitCode, 73, reason: result.stderr.toString());
        // Worker uses the existing fixture slot naming convention.
        final current = await reopen().current();
        expect(current!.value, point == 'published' ? 'after' : 'before');
        final expectedVersion =
            [
              'upgradeCatalogWriting',
              'upgradeRecording',
              'upgradePrepared',
            ].contains(point)
            ? 2
            : 3;
        expect(await inspectCatalog((db) => db.userVersion), expectedVersion);
        final retry = await store.upgrade(request, (_) async => prepared());
        expect(
          (await store.current())!.receipt.generation,
          retry.target.generation,
        );
        expect(
          await inspectCatalog(
            (db) => db.select(
              "SELECT generation FROM attempts WHERE operation=? AND status='committed'",
              [request.operation.toString()],
            ).length,
          ),
          1,
        );
      },
    );
  }

  test('aborted upgrade reserves its operation identity but permits an identical retry', () async {
    await expectLater(
      store.upgrade(
        request,
        (_) async => prepared(),
        checkpoint: (at) {
          if (at == 'reserved') throw StateError('injected');
        },
      ),
      unavailable,
    );
    await expectLater(store.install('after', request.operation), conflict);
    await store.upgrade(request, (_) async => prepared());
    expect(
      await inspectCatalog((db) => db.select('SELECT * FROM upgrades').length),
      2,
    );
  });

  test('tampered upgrade linkage is rejected without changing the active reference', () async {
    final upgraded = await store.upgrade(request, (_) async => prepared());
    await inspectCatalog(
      (db) => db.execute('UPDATE upgrades SET backup_digest=?', ['bad']),
    );
    await expectLater(store.current(), unavailable);
    expect(
      await inspectCatalog(
        (db) => db.select('SELECT generation FROM active').single['generation'],
      ),
      upgraded.target.generation.value,
    );
  });

  test(
    'retry cannot silently replace the prepared target or backup contents',
    () async {
      await expectLater(
        store.upgrade(
          request,
          (_) async => prepared(),
          checkpoint: (at) {
            if (at == 'reserved') throw StateError('injected');
          },
        ),
        unavailable,
      );
      for (final changed in [
        PreparedUpgrade('different', prepared().backupDigest),
        PreparedUpgrade('after', digest('different-backup')),
      ]) {
        await expectLater(
          store.upgrade(request, (_) async => changed),
          conflict,
        );
        expect((await store.current())!.value, 'before');
      }
      await store.upgrade(request, (_) async => prepared());
      expect((await store.current())!.value, 'after');
    },
  );

  test(
    'upgrade of a missing store cannot initialize catalog or key slots',
    () async {
      final fresh = GenerationStore(
        Directory('${work.path}/missing'),
        slots,
        catalogProtection: fixtureCatalogProtection(slots),
        upgradeAware: true,
      );
      final keyCount = slots.directory.listSync().length;
      await expectLater(
        fresh.upgrade(request, (_) async => throw StateError('must not run')),
        unavailable,
      );
      expect(File('${work.path}/missing/catalog.db').existsSync(), isFalse);
      expect(
        File('${work.path}/missing/catalog.init.db').existsSync(),
        isFalse,
      );
      expect(slots.directory.listSync().length, keyCount);
    },
  );

  test('preparation retains the lifecycle lease until publication', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final upgrading = store.upgrade(request, (_) async {
      entered.complete();
      await release.future;
      return prepared();
    });
    await entered.future;
    try {
      await expectLater(
        reopen().current(),
        throwsA(
          isA<GenerationUnavailable>().having(
            (e) => e.problem,
            'problem',
            GenerationProblem.busy,
          ),
        ),
      );
    } finally {
      release.complete();
    }
    await upgrading;
    expect((await store.current())!.value, 'after');
  });

  test(
    'unknown catalog version rejects before preparation or new DDL',
    () async {
      await inspectCatalog((db) => db.execute('PRAGMA user_version=999'));
      final bytes = File('${work.path}/store/catalog.db').readAsBytesSync();
      await expectLater(
        store.upgrade(request, (_) async => throw StateError('must not run')),
        unavailable,
      );
      expect(File('${work.path}/store/catalog.db').readAsBytesSync(), bytes);
    },
  );

  test('upgrade mode requires encryption; fresh mode creates a validated empty catalog', () async {
    expect(
      () => GenerationStore(
        Directory('${work.path}/bad'),
        slots,
        upgradeAware: true,
      ),
      throwsArgumentError,
    );
    final fresh = GenerationStore(
      Directory('${work.path}/fresh'),
      slots,
      catalogProtection: fixtureCatalogProtection(slots),
      upgradeAware: true,
    );
    expect(await fresh.current(), isNull);
    expect(
      () => oldStore.upgrade(request, (_) async => prepared()),
      throwsStateError,
    );
  });
}
