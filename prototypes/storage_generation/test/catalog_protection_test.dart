import 'dart:convert';
import 'dart:io';

import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:storage_generation_probe/catalog_protection.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:test/test.dart';

const oldId = '019f0000-0000-7000-8000-000000000001';
const newId = '019f0000-0000-7000-8000-000000000002';

void main() {
  final parent = Directory('.dart_tool/protected-tests')
    ..createSync(recursive: true);
  late Directory owned;
  late Directory root;
  late FixtureKeySlots slots;
  late CatalogProtection protection;
  late GenerationStore store;
  setUp(() {
    owned = parent.createTempSync('case-');
    root = Directory('${owned.path}/store');
    slots = FixtureKeySlots(Directory('${root.path}-keys'));
    protection = fixtureCatalogProtection(slots);
    store = GenerationStore(root, slots, catalogProtection: protection);
  });
  tearDown(() {
    if (!owned.absolute.path.startsWith(
      '${parent.absolute.path}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    owned.deleteSync(recursive: true);
  });
  File catalog() => File('${root.path}/catalog.db');
  File keyFile() =>
      File('${slots.directory.path}/${protection.identity.value}.key');
  Future<GenerationReceipt> install() =>
      store.install('old fixture', OperationId.parse(oldId));
  Future<ProcessResult> child(
    String point, {
    String action = 'install',
    String value = 'new fixture',
    String id = newId,
  }) => Process.run(
    File(
      '.dart_tool/worker/bundle/bin/generation_worker${Platform.isWindows ? '.exe' : ''}',
    ).absolute.path,
    [action, root.absolute.path, id, value, point, 'protected'],
  );

  test(
    'encrypted catalog hides fingerprints and uses independent dedicated key',
    () async {
      final receipt = await install();
      final bytes = latin1.decode(catalog().readAsBytesSync());
      expect(bytes, isNot(startsWith('SQLite format 3')));
      expect(bytes, isNot(contains(receipt.fingerprint)));
      expect(bytes, isNot(contains(receipt.slot.value)));
      final plain = sqlite3.open(catalog().path);
      try {
        expect(() => plain.select('SELECT * FROM attempts'), throwsA(anything));
      } finally {
        plain.close();
      }
      final wrong = sqlite3.open(catalog().path);
      try {
        expect(
          () => configureEncryption(wrong, StorageKey.random()),
          throwsA(isA<EncryptedStorageUnavailable>()),
        );
      } finally {
        wrong.close();
      }
      expect(
        (await child(
          'none',
          action: 'verify',
          value: 'old fixture',
          id: oldId,
        )).exitCode,
        0,
      );
      expect(
        keyFile().readAsStringSync(),
        isNot(
          File('${slots.directory.path}/${receipt.slot.value}.key')
              .readAsStringSync(),
        ),
      );
    },
  );

  for (final point in [
    'reserved',
    'databaseWriting',
    'staged',
    'publishing',
    'published',
  ]) {
    test('protected catalog recovers process interruption at $point', () async {
      final original = await install();
      final key = keyFile().readAsBytesSync();
      expect((await child(point)).exitCode, 73);
      expect(
        (await store.current())!.value,
        point == 'published' ? 'new fixture' : 'old fixture',
      );
      await store.install('new fixture', OperationId.parse(newId));
      expect((await store.current())!.value, 'new fixture');
      expect(keyFile().readAsBytesSync(), key);
      expect(await store.databaseFile(original.generation).exists(), isTrue);
    });
  }

  test(
    'journal during publication does not reveal installation fingerprint',
    () async {
      final receipt = await install();
      await store.install(
        'new fixture',
        OperationId.parse(newId),
        checkpoint: (point) {
          if (point == 'publishing') {
            final journal = File('${catalog().path}-journal');
            expect(journal.existsSync(), isTrue);
            final raw = latin1.decode(journal.readAsBytesSync());
            expect(raw, isNot(contains(oldId)));
            expect(raw, isNot(contains('old fixture')));
            expect(raw, isNot(contains(receipt.fingerprint)));
          }
        },
      );
    },
  );

  for (final point in [
    'catalogKeyReady',
    'catalogOpened',
    'catalogWriting',
    'catalogStaged',
    'catalogValidated',
    'catalogPublishing',
    'catalogPublished',
    'catalogReady',
  ]) {
    test(
      'first initialization exit at $point reuses saved key safely',
      () async {
        expect((await child(point)).exitCode, 73);
        final saved = keyFile().readAsBytesSync();
        expect(await store.current(), isNull);
        expect((await child('none')).exitCode, 0);
        expect(keyFile().readAsBytesSync(), saved);
        expect((await store.current())!.value, 'new fixture');
        expect(File('${root.path}/catalog.init.db').existsSync(), isFalse);
      },
    );
  }
  test('incomplete published catalog is retained and never reset', () async {
    expect((await child('catalogWriting')).exitCode, 73);
    // Recreate the previous-version partial published path, not a new stage.
    final stage = File('${root.path}/catalog.init.db');
    final partial = sqlite3.open(stage.path);
    configureEncryption(partial, await protection.loadKey(true));
    expect(partial.userVersion, 0);
    partial.close();
    stage.renameSync(catalog().path);
    final key = keyFile().readAsBytesSync();
    final before = catalog().readAsBytesSync();
    await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
    expect(catalog().existsSync(), isTrue);
    expect(catalog().readAsBytesSync(), before);
    expect(keyFile().readAsBytesSync(), key);
    expect(root.listSync().where((e) => e.path.contains('gen-')), isEmpty);
  });

  for (final mutation in [
    'version',
    'column',
    'contents',
    'identity',
    'tamper',
  ]) {
    test(
      'unknown or invalid initialization $mutation is never replaced',
      () async {
        expect((await child('catalogStaged')).exitCode, 73);
        final stage = File('${root.path}/catalog.init.db');
        if (mutation == 'tamper') {
          final bytes = stage.readAsBytesSync();
          bytes[100] ^= 1;
          stage.writeAsBytesSync(bytes, flush: true);
        } else {
          final raw = sqlite3.open(stage.path);
          configureEncryption(raw, await protection.loadKey(true));
          switch (mutation) {
            case 'version':
              raw.execute('PRAGMA user_version=99');
            case 'column':
              raw.execute(
                "ALTER TABLE active ADD COLUMN future TEXT GENERATED ALWAYS AS ('x') VIRTUAL",
              );
            case 'contents':
              raw.execute('INSERT INTO attempts VALUES(?,?,?,?,?,NULL)', [
                oldId,
                newId,
                oldId,
                List.filled(64, 'a').join(),
                'aborted',
              ]);
            case 'identity':
              raw.execute('UPDATE catalog_identity SET identity=?', [oldId]);
          }
          raw.close();
        }
        final before = stage.readAsBytesSync();
        final key = keyFile().readAsBytesSync();
        await expectLater(
          store.current(),
          throwsA(isA<GenerationUnavailable>()),
        );
        expect(stage.readAsBytesSync(), before);
        expect(keyFile().readAsBytesSync(), key);
        expect(catalog().existsSync(), isFalse);
      },
    );
  }

  test('stage with lost key cannot create a replacement', () async {
    expect((await child('catalogStaged')).exitCode, 73);
    final stage = File('${root.path}/catalog.init.db');
    final before = stage.readAsBytesSync();
    keyFile().deleteSync();
    await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
    expect(keyFile().existsSync(), isFalse);
    expect(stage.readAsBytesSync(), before);
    expect(catalog().existsSync(), isFalse);
  });

  test('existing catalog and a stage are a conflict, neither wins', () async {
    await install();
    final before = catalog().readAsBytesSync();
    final stage = catalog().copySync('${root.path}/catalog.init.db');
    await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
    expect(catalog().readAsBytesSync(), before);
    expect(stage.readAsBytesSync(), before);
  });

  test(
    'retained generations prevent stage from replacing a lost catalog',
    () async {
      final receipt = await install();
      final stage = catalog().renameSync('${root.path}/catalog.init.db');
      final before = stage.readAsBytesSync();
      await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
      expect(catalog().existsSync(), isFalse);
      expect(stage.readAsBytesSync(), before);
      expect(store.databaseFile(receipt.generation).existsSync(), isTrue);
    },
  );

  for (final suffix in ['-journal', '-wal', '-shm']) {
    test(
      'orphan initialization $suffix is retained without creating keys',
      () async {
        root.createSync(recursive: true);
        final sidecar = File('${root.path}/catalog.init.db$suffix')
          ..writeAsStringSync('retain');
        await expectLater(
          store.current(),
          throwsA(isA<GenerationUnavailable>()),
        );
        expect(catalog().existsSync(), isFalse);
        expect(sidecar.readAsStringSync(), 'retain');
        expect(keyFile().existsSync(), isFalse);
      },
    );
  }
  test('lost catalog key fails without generating a replacement', () async {
    await install();
    keyFile().deleteSync();
    final before = catalog().readAsBytesSync();
    await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
    expect(keyFile().existsSync(), isFalse);
    expect(catalog().readAsBytesSync(), before);
  });
  test(
    'lost catalog with retained generations refuses fresh initialization',
    () async {
      await install();
      catalog().deleteSync();
      final before = keyFile().readAsBytesSync();
      await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
      expect(catalog().existsSync(), isFalse);
      expect(keyFile().readAsBytesSync(), before);
    },
  );
  test(
    'matching decryption key cannot bypass a wrong store identity',
    () async {
      await install();
      final before = catalog().readAsBytesSync();
      final wrong = GenerationStore(
        root,
        slots,
        catalogProtection: CatalogProtection(
          PublicId.generate(),
          protection.loadKey,
        ),
      );
      await expectLater(wrong.current(), throwsA(isA<GenerationUnavailable>()));
      expect(catalog().readAsBytesSync(), before);
    },
  );
  test(
    'legacy plaintext is not silently migrated or accepted as protected',
    () async {
      final legacy = GenerationStore(root, slots);
      await legacy.install('old fixture', OperationId.parse(oldId));
      final before = catalog().readAsBytesSync();
      await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
      expect(catalog().readAsBytesSync(), before);
      expect(keyFile().existsSync(), isFalse);
      await slots.create(protection.identity);
      final key = keyFile().readAsBytesSync();
      await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
      expect(catalog().readAsBytesSync(), before);
      expect(keyFile().readAsBytesSync(), key);
      expect((await legacy.current())!.value, 'old fixture');
    },
  );
  test('protected catalog cannot fall back to plaintext mode', () async {
    await install();
    final before = catalog().readAsBytesSync();
    await expectLater(
      GenerationStore(root, slots).current(),
      throwsA(isA<GenerationUnavailable>()),
    );
    expect(catalog().readAsBytesSync(), before);
  });
  for (final mutation in ['version', 'column', 'tamper']) {
    test('protected catalog rejects $mutation without key reset', () async {
      await install();
      if (mutation == 'tamper') {
        final bytes = catalog().readAsBytesSync();
        bytes[100] ^= 1;
        catalog().writeAsBytesSync(bytes, flush: true);
      } else {
        final db = sqlite3.open(catalog().path);
        configureEncryption(db, await protection.loadKey(true));
        db.execute(
          mutation == 'version' ? 'PRAGMA user_version=99' : "ALTER TABLE catalog_identity ADD COLUMN future TEXT GENERATED ALWAYS AS ('x') VIRTUAL",
        );
        db.close();
      }
      final key = keyFile().readAsBytesSync();
      await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
      expect(keyFile().readAsBytesSync(), key);
    });
  }
}
