import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/chunked_snapshot.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  late Directory root;
  late ChunkedSnapshotStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('chunked-snapshot-');
    store = const ChunkedSnapshotStore(
      maxChunkBytes: 160,
      maxRowsPerChunk: 2,
      maxTotalRows: 20,
      maxTotalBytes: 2000,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  Map<String, Stream<Map<String, Object?>>> rows() => {
    'accounts': Stream.fromIterable([
      {'id': 'b', 'name': 'B'},
      {'id': 'a', 'name': 'A'},
      {'id': 'c', 'name': 'C'},
    ]),
    'events': Stream.fromIterable([
      {'amount': '10', 'id': 'e1'},
      {'amount': '-3', 'id': 'e2'},
    ]),
  };

  test('writes bounded deterministic chunks and verifies totals', () async {
    final target = Directory('${root.path}/snapshot');
    final summary = await store.write(
      target: target,
      schema: 24,
      tables: rows(),
    );
    expect(summary.totalRows, 5);
    expect(summary.chunkCount, 3);
    expect(
      (await store.verify(
        target,
        expectedTables: ['accounts', 'events'],
      )).totalBytes,
      summary.totalBytes,
    );
    expect(
      File('${target.path}/chunk-00000000.ndjson').readAsStringSync(),
      '{"id":"b","name":"B"}\n{"id":"a","name":"A"}\n',
    );
  });

  test('tamper, missing and extra files all fail closed', () async {
    for (final damage in ['tamper', 'missing', 'extra']) {
      final target = Directory('${root.path}/$damage');
      await store.write(target: target, schema: 24, tables: rows());
      if (damage == 'tamper') {
        File('${target.path}/chunk-00000000.ndjson').writeAsStringSync('bad\n');
      } else if (damage == 'missing') {
        File('${target.path}/chunk-00000000.ndjson').deleteSync();
      } else {
        File('${target.path}/unexpected').writeAsStringSync('x');
      }
      await expectLater(
        store.verify(target, expectedTables: ['accounts', 'events']),
        throwsA(isA<InvalidChunkedSnapshot>()),
      );
    }
  });

  test(
    'manifest table order, totals and chunk sequence are authority',
    () async {
      for (final damage in ['table', 'total', 'ordinal']) {
        final target = Directory('${root.path}/$damage');
        await store.write(target: target, schema: 24, tables: rows());
        final file = File('${target.path}/manifest.json');
        final manifest = jsonDecode(file.readAsStringSync()) as Map;
        if (damage == 'table') {
          (manifest['tables'] as List).first['name'] = 'events';
        } else if (damage == 'total') {
          manifest['totalRows'] = 4;
        } else {
          ((manifest['tables'] as List).first['chunks'] as List)
                  .first['ordinal'] =
              8;
        }
        final bytes = utf8.encode(jsonEncode(manifest));
        file.writeAsBytesSync(bytes, flush: true);
        final digest = (await Sha256().hash(bytes)).bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
        File('${target.path}/manifest.sha256')
            .writeAsStringSync(digest, flush: true);
        await expectLater(
          store.verify(target, expectedTables: ['accounts', 'events']),
          throwsA(isA<InvalidChunkedSnapshot>()),
        );
      }
    },
  );

  test('oversize row leaves no target or temporary directory', () async {
    final target = Directory('${root.path}/oversize');
    await expectLater(
      store.write(
        target: target,
        schema: 24,
        tables: {
          'events': Stream.value({'value': List.filled(500, 'x').join()}),
        },
      ),
      throwsA(isA<InvalidChunkedSnapshot>()),
    );
    expect(target.existsSync(), isFalse);
    expect(root.listSync(), isEmpty);
  });

  test('existing target and invalid table names are rejected', () async {
    final existing = Directory('${root.path}/existing')..createSync();
    await expectLater(
      store.write(target: existing, schema: 24, tables: rows()),
      throwsStateError,
    );
    await expectLater(
      store.write(
        target: Directory('${root.path}/bad-name'),
        schema: 24,
        tables: {'../events': const Stream.empty()},
      ),
      throwsA(isA<InvalidChunkedSnapshot>()),
    );
  });

  test(
    'snapshot codec streams real authority by stable primary keys',
    () async {
      final databaseFile = File('${root.path}/source.db');
      final legacy = sqlite3.open(databaseFile.path);
      try {
        legacy.execute(
          File('../modular_persistence/test/fixtures/v1.sql')
              .readAsStringSync(),
        );
      } finally {
        legacy.close();
      }
      final database = ProbeDatabase(databaseFile);
      final checkpoints = <String>[];
      const authorityStore = ChunkedSnapshotStore(
        maxChunkBytes: 4096,
        maxRowsPerChunk: 2,
        maxTotalRows: 100,
        maxTotalBytes: 65536,
      );
      try {
        final target = Directory('${root.path}/authority');
        final summary = await SnapshotCodec().captureChunked(
          database,
          target,
          store: authorityStore,
          pageSize: 1,
          checkpoint: (table, rows) => checkpoints.add('$table:$rows'),
        );
        expect(summary.schema, 2);
        expect(summary.totalRows, greaterThan(0));
        expect(checkpoints, containsAll(['events:1', 'events:2']));
        expect(
          await authorityStore.verify(
            target,
            expectedTables: const [
              'accounts',
              'events',
              'legs',
              'openings',
              'allocations',
              'receipts',
              'audit',
            ],
          ),
          isA<ChunkedSnapshotSummary>(),
        );
      } finally {
        await database.close();
      }
    },
  );
}
