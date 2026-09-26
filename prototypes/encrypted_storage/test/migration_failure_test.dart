import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/migration-failure-tests')
    ..createSync(recursive: true);
  late Directory work;
  late File file;
  late File keyFile;
  late StorageKey key;
  setUp(() {
    work = root.createTempSync('case-');
    file = File('${work.path}/current.db');
    final random = Random.secure();
    final bytes = List.generate(32, (_) => random.nextInt(256));
    keyFile = File('${work.path}/key.bin')..writeAsBytesSync(bytes);
    key = StorageKey(bytes);
    final raw = sqlite3.open(file.path);
    try {
      configureEncryption(raw, key);
      raw.execute(
        File('../modular_persistence/test/fixtures/v1.sql').readAsStringSync(),
      );
    } finally {
      raw.close();
    }
  });
  tearDown(() {
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup.');
    work.deleteSync(recursive: true);
  });
  Map<String, Object?> oldSnapshot({int version = 1}) {
    final raw = sqlite3.open(file.path);
    try {
      configureEncryption(raw, key);
      expect(raw.select('PRAGMA user_version').single.values.single, version);
      expect(raw.select('PRAGMA integrity_check').single.values.single, 'ok');
      expect(raw.select('PRAGMA cipher_integrity_check'), isEmpty);
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      expect(
        raw.select('PRAGMA table_info(events)').map((r) => r['name']),
        isNot(contains('source_context')),
      );
      expect(
        raw.select(
          "SELECT name FROM sqlite_master WHERE name='legs_by_account'",
        ),
        isEmpty,
      );
      return {
        for (final table in [
          'accounts',
          'events',
          'legs',
          'openings',
          'allocations',
          'receipts',
          'audit',
        ])
          table: raw
              .select('SELECT * FROM $table ORDER BY rowid')
              .map((r) => Map<String, Object?>.from(r))
              .toList(),
      };
    } finally {
      raw.close();
    }
  }

  Future<void> retry() async {
    final db = openEncrypted(file, key);
    try {
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        2,
      );
      await SnapshotCodec().validate(db);
      expect(
        (await db.customSelect('SELECT SUM(amount) AS n FROM legs').getSingle())
            .read<int>('n'),
        11500,
      );
    } finally {
      await db.close();
    }
  }

  for (final point in ['column', 'index']) {
    test('encrypted migration process exit after $point retains v1 and can retry', () async {
      final before = oldSnapshot();
      final binary = File(
        '.dart_tool/worker/bundle/bin/restore_worker${Platform.isWindows ? '.exe' : ''}',
      );
      final result = await Process.run(binary.absolute.path, [
        'migrate',
        work.absolute.path,
        keyFile.absolute.path,
        point,
      ], workingDirectory: work.absolute.path);
      expect(result.exitCode, 73, reason: '${result.stdout}\n${result.stderr}');
      final journal = File('${file.path}-journal');
      expect(journal.existsSync(), isTrue);
      expect(journal.lengthSync(), greaterThan(0));
      expect(
        latin1.decode(journal.readAsBytesSync()),
        isNot(contains('Frozen fixture')),
      );
      // Open with the correct key: SQLite, not file renames, recovers its hot journal.
      expect(oldSnapshot(), before);
      await retry();
    });
  }
  test(
    'engine SQLITE_FULL during encrypted upgrade rolls schema and rows back',
    () async {
      final before = oldSnapshot();
      final checkpoints = <String>[];
      final db = ProbeDatabase.withExecutor(
        NativeDatabase(
          file,
          setup: (raw) {
            configureEncryption(raw, key);
            expect(raw.select('PRAGMA freelist_count').single.values.single, 0);
            final pages =
                raw.select('PRAGMA page_count').single.values.single as int;
            expect(
              raw.select('PRAGMA max_page_count = $pages').single.values.single,
              pages,
            );
          },
        ),
        migrationCheckpoint: checkpoints.add,
      );
      try {
        await expectLater(
          db.customSelect('SELECT * FROM events').get(),
          throwsA(
            isA<SqliteException>().having(
              (e) => e.resultCode,
              'SQLITE_FULL',
              13,
            ),
          ),
        );
      } finally {
        await db.close();
      }
      expect(checkpoints, contains('column'));
      expect(checkpoints, isNot(contains('index')));
      expect(oldSnapshot(), before);
      await retry();
    },
  );
  test(
    'unknown encrypted schema refuses downgrade without modifying history',
    () async {
      final raw = sqlite3.open(file.path);
      try {
        configureEncryption(raw, key);
        raw.execute('PRAGMA user_version = 99');
      } finally {
        raw.close();
      }
      final before = oldSnapshot(version: 99);
      final bytes = file.readAsBytesSync();
      final db = openEncrypted(file, key);
      try {
        await expectLater(
          db.customSelect('SELECT * FROM events').get(),
          throwsStateError,
        );
      } finally {
        await db.close();
      }
      expect(file.readAsBytesSync(), bytes);
      expect(oldSnapshot(version: 99), before);
    },
  );
}
