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

  for (final point in ['catalogKeyReady', 'catalogReady']) {
    test(
      'first initialization exit at $point reuses saved key safely',
      () async {
        expect((await child(point)).exitCode, 73);
        final saved = keyFile().readAsBytesSync();
        await store.install('new fixture', OperationId.parse(newId));
        expect(keyFile().readAsBytesSync(), saved);
        expect((await store.current())!.value, 'new fixture');
      },
    );
  }
  test(
    'interrupted catalog schema creation is retained and never reset',
    () async {
      expect((await child('catalogWriting')).exitCode, 73);
      final key = keyFile().readAsBytesSync();
      await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
      expect(catalog().existsSync(), isTrue);
      expect(keyFile().readAsBytesSync(), key);
      expect(root.listSync().where((e) => e.path.contains('gen-')), isEmpty);
    },
  );
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
