import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:storage_generation_probe/key_slots.dart';
import 'package:test/test.dart';

const oldId = '019f0000-0000-7000-8000-000000000001';
const newId = '019f0000-0000-7000-8000-000000000002';
const oldValue = 'old synthetic ledger marker';
const newValue = 'new synthetic ledger marker';

final class FailingSlots implements KeySlots {
  FailingSlots(this.delegate, {this.afterWrite = false});
  final KeySlots delegate;
  final bool afterWrite;
  @override
  Future<void> create(PublicId slot) async {
    if (afterWrite) await delegate.create(slot);
    throw StateError('sensitive fixture diagnostic');
  }

  @override
  Future<StorageKey> read(PublicId slot) => delegate.read(slot);
}

final class PausedSlots implements KeySlots {
  PausedSlots(this.delegate);
  final KeySlots delegate;
  final entered = Completer<void>();
  final resume = Completer<void>();
  @override
  Future<void> create(PublicId slot) async {
    entered.complete();
    await resume.future;
    await delegate.create(slot);
  }

  @override
  Future<StorageKey> read(PublicId slot) => delegate.read(slot);
}

void main() {
  late Directory root;
  late FixtureKeySlots slots;
  late GenerationStore store;
  final worker = File(
    '.dart_tool/worker/bundle/bin/generation_worker${Platform.isWindows ? '.exe' : ''}',
  ).absolute;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('generation-fixture-');
    slots = FixtureKeySlots(Directory('${root.path}/keys'));
    store = GenerationStore(root, slots);
  });
  tearDown(() async => root.delete(recursive: true));

  Future<ProcessResult> child(
    String action,
    String id,
    String value, [
    String point = '-',
  ]) => Process.run(worker.path, [action, root.path, id, value, point]);
  Future<GenerationReceipt> installOld() =>
      store.install(oldValue, OperationId.parse(oldId));

  test(
    'publishes a paired encrypted generation and retains old database and key',
    () async {
      final old = await installOld();
      final next = await store.install(newValue, OperationId.parse(newId));
      expect(next.generation, isNot(old.generation));
      expect(next.slot, isNot(old.slot));
      expect((await store.current())!.value, newValue);
      expect(await store.databaseFile(old.generation).exists(), isTrue);
      for (final ref in [old, next]) {
        final bytes = latin1.decode(
          await store.databaseFile(ref.generation).readAsBytes(),
        );
        expect(bytes.startsWith('SQLite format 3'), isFalse);
        expect(bytes.contains('synthetic ledger marker'), isFalse);
        await slots.read(ref.slot);
      }
      final wrong = sqlite3.open(
        store.databaseFile(old.generation).path,
        mode: OpenMode.readOnly,
      );
      try {
        final key = await slots.read(next.slot);
        expect(
          () => configureEncryption(wrong, key),
          throwsA(isA<EncryptedStorageUnavailable>()),
        );
      } finally {
        wrong.close();
      }
      expect((await child('verify', newId, newValue)).exitCode, 0);
    },
  );

  test(
    'replay of earlier committed operation does not reactivate its generation',
    () async {
      final old = await installOld();
      await store.install(newValue, OperationId.parse(newId));
      final replay = await store.install(oldValue, OperationId.parse(oldId));
      expect(replay.generation, old.generation);
      expect((await store.current())!.value, newValue);
      await expectLater(
        store.install('different input', OperationId.parse(oldId)),
        throwsA(
          isA<GenerationUnavailable>().having(
            (e) => e.problem,
            'problem',
            GenerationProblem.operationConflict,
          ),
        ),
      );
    },
  );

  for (final point in [
    'reserved',
    'keySaved',
    'databaseWriting',
    'staged',
    'validated',
    'publishing',
    'published',
  ]) {
    test(
      'fresh process interrupted at $point recovers the committed pair',
      () async {
        final old = await installOld();
        expect((await child('install', newId, newValue, point)).exitCode, 73);
        final published = point == 'published';
        expect(
          (await child(
            'verify',
            published ? newId : oldId,
            published ? newValue : oldValue,
          )).exitCode,
          0,
        );
        final before = (await store.current())!.receipt;
        final next = await store.install(newValue, OperationId.parse(newId));
        if (published) expect(next.generation, before.generation);
        expect((await store.current())!.value, newValue);
        expect(await store.databaseFile(old.generation).exists(), isTrue);
        await slots.read(old.slot);
      },
    );
  }

  for (final point in [
    'keySaved',
    'databaseWriting',
    'publishing',
    'published',
  ]) {
    test(
      'first install interrupted at $point never invents an active generation',
      () async {
        expect((await child('install', newId, newValue, point)).exitCode, 73);
        expect(
          (await child(
            'verify',
            newId,
            point == 'published' ? newValue : '<none>',
          )).exitCode,
          0,
        );
        await store.install(newValue, OperationId.parse(newId));
        expect((await store.current())!.value, newValue);
      },
    );
  }

  test(
    'failed key creation preserves old pair and sanitized error permits retry',
    () async {
      final old = await installOld();
      final failing = GenerationStore(root, FailingSlots(slots));
      await expectLater(
        failing.install(newValue, OperationId.parse(newId)),
        throwsA(
          isA<GenerationUnavailable>().having(
            (e) => e.toString(),
            'redacted',
            isNot(contains('sensitive')),
          ),
        ),
      );
      expect((await store.current())!.receipt.generation, old.generation);
      await store.install(newValue, OperationId.parse(newId));
      expect((await store.current())!.value, newValue);
    },
  );

  test(
    'failure after key persistence retains the orphan slot and old pair',
    () async {
      final old = await installOld();
      final failing = GenerationStore(
        root,
        FailingSlots(slots, afterWrite: true),
      );
      await expectLater(
        failing.install(newValue, OperationId.parse(newId)),
        throwsA(isA<GenerationUnavailable>()),
      );
      expect((await store.current())!.receipt.generation, old.generation);
      expect(await Directory('${root.path}/keys').list().length, 2);
      await store.install(newValue, OperationId.parse(newId));
      expect(await Directory('${root.path}/keys').list().length, 3);
      expect((await store.current())!.value, newValue);
    },
  );

  test('unknown key encoding is never replaced automatically', () async {
    final old = await installOld();
    final file = File('${root.path}/keys/${old.slot.value}.key');
    await file.writeAsString('v2:${base64Encode(List.filled(32, 7))}');
    final before = await file.readAsBytes();
    await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
    expect(await file.readAsBytes(), before);
  });

  test(
    'unknown catalog generated column is rejected without dropping it',
    () async {
      await installOld();
      final catalog = sqlite3.open('${root.path}/catalog.db');
      try {
        catalog.execute(
          'ALTER TABLE active ADD COLUMN future INTEGER GENERATED ALWAYS AS (1) VIRTUAL',
        );
      } finally {
        catalog.close();
      }
      final before = await File('${root.path}/catalog.db').readAsBytes();
      await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
      expect(await File('${root.path}/catalog.db').readAsBytes(), before);
    },
  );

  test(
    'changed encrypted fixture content does not pass identity-only validation',
    () async {
      final old = await installOld();
      final db = sqlite3.open(store.databaseFile(old.generation).path);
      try {
        configureEncryption(db, await slots.read(old.slot));
        db.execute('UPDATE fixture SET value=?', ['changed marker']);
      } finally {
        db.close();
      }
      await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
    },
  );

  test(
    'unexpected generation sidecar is preserved and stops reopening',
    () async {
      final old = await installOld();
      final sidecar = File(
        '${store.databaseFile(old.generation).path}-journal',
      );
      await sidecar.writeAsString('unknown fixture sidecar');
      await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
      expect(await sidecar.readAsString(), 'unknown fixture sidecar');
    },
  );

  test('lost key fails closed without replacing the missing slot', () async {
    final old = await installOld();
    final file = File('${root.path}/keys/${old.slot.value}.key');
    await file.delete();
    final before = await store.databaseFile(old.generation).readAsBytes();
    await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
    await expectLater(
      store.install(newValue, OperationId.parse(newId)),
      throwsA(isA<GenerationUnavailable>()),
    );
    expect(await file.exists(), isFalse);
    expect(await store.databaseFile(old.generation).readAsBytes(), before);
  });

  test(
    'catalog cannot pair a retained database with another generation key',
    () async {
      final old = await installOld();
      final next = await store.install(newValue, OperationId.parse(newId));
      final catalog = sqlite3.open('${root.path}/catalog.db');
      try {
        catalog.execute('UPDATE attempts SET slot=? WHERE generation=?', [
          PublicId.generate().value,
          next.generation.value,
        ]);
        catalog.execute('UPDATE attempts SET slot=? WHERE generation=?', [
          next.slot.value,
          old.generation.value,
        ]);
        catalog.execute('UPDATE active SET generation=?', [
          old.generation.value,
        ]);
      } finally {
        catalog.close();
      }
      await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
      expect(await store.databaseFile(old.generation).exists(), isTrue);
      expect(await store.databaseFile(next.generation).exists(), isTrue);
    },
  );

  test(
    'database identity mismatch is rejected even when the key decrypts',
    () async {
      final old = await installOld();
      final db = sqlite3.open(store.databaseFile(old.generation).path);
      try {
        configureEncryption(db, await slots.read(old.slot));
        db.execute('UPDATE identity SET generation=?', [
          PublicId.generate().value,
        ]);
      } finally {
        db.close();
      }
      await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
    },
  );

  test(
    'missing catalog with retained generations does not create an empty store',
    () async {
      final old = await installOld();
      await File('${root.path}/catalog.db').delete();
      await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
      expect(await File('${root.path}/catalog.db').exists(), isFalse);
      expect(await store.databaseFile(old.generation).exists(), isTrue);
    },
  );

  test(
    'unknown catalog version fails without changing it or key material',
    () async {
      final old = await installOld();
      final catalog = sqlite3.open('${root.path}/catalog.db');
      try {
        catalog.execute('PRAGMA user_version=99');
      } finally {
        catalog.close();
      }
      final before = await File('${root.path}/catalog.db').readAsBytes();
      final keyBefore = await File('${root.path}/keys/${old.slot.value}.key')
          .readAsBytes();
      await expectLater(store.current(), throwsA(isA<GenerationUnavailable>()));
      expect(await File('${root.path}/catalog.db').readAsBytes(), before);
      expect(
        await File('${root.path}/keys/${old.slot.value}.key').readAsBytes(),
        keyBefore,
      );
    },
  );

  test(
    'second coordinator cannot publish while a first holds its lifecycle lease',
    () async {
      await installOld();
      final paused = PausedSlots(slots);
      final installing = GenerationStore(
        root,
        paused,
      ).install(newValue, OperationId.parse(newId));
      await paused.entered.future;
      try {
        await expectLater(
          store.current(),
          throwsA(
            isA<GenerationUnavailable>().having(
              (e) => e.problem,
              'problem',
              GenerationProblem.busy,
            ),
          ),
        );
      } finally {
        paused.resume.complete();
      }
      await installing;
      expect((await store.current())!.value, newValue);
    },
  );

  test(
    'two independent processes with one operation publish only one generation',
    () async {
      await installOld();
      final results = await Future.wait([
        child('install', newId, newValue),
        child('install', newId, newValue),
      ]);
      expect(results.map((r) => r.exitCode), everyElement(0));
      final catalog = sqlite3.open('${root.path}/catalog.db');
      try {
        expect(
          catalog.select(
            "SELECT count(*) AS n FROM attempts WHERE operation=? AND status='committed'",
            [newId],
          ).single['n'],
          1,
        );
      } finally {
        catalog.close();
      }
      expect((await store.current())!.value, newValue);
    },
  );
}
