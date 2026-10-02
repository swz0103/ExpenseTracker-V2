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

  test(
    'streamed capacity exactly matches canonical conservative usage',
    () async {
      final databaseFile = File('${root.path}/capacity-source.db');
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
      try {
        final codec = SnapshotCodec();
        final canonical = await codec.capture(database);
        final decoded = jsonDecode(utf8.decode(canonical)) as Map;
        final tables = decoded['tables'] as Map;
        final expectedRows = tables.values.fold<int>(
          0,
          (sum, rows) => sum + (rows as List).length,
        );
        final nonempty = tables.values.where(
          (rows) => (rows as List).isNotEmpty,
        );
        var callbacks = 0;
        final inspection = await codec.inspectCapacity(
          database,
          pageSize: 1,
          onRow: (_, _) => callbacks++,
        );
        expect(inspection.rows, expectedRows);
        expect(inspection.bytes, canonical.length + nonempty.length);
        expect(callbacks, expectedRows);
        expect(
          inspection.tableRows.values.fold<int>(0, (sum, count) => sum + count),
          expectedRows,
        );
      } finally {
        await database.close();
      }
    },
  );

  test('chunked stage recreates equivalent authority in a new file', () async {
    final sourceFile = File('${root.path}/roundtrip-source.db');
    final legacy = sqlite3.open(sourceFile.path);
    try {
      legacy.execute(
        File('../modular_persistence/test/fixtures/v1.sql').readAsStringSync(),
      );
    } finally {
      legacy.close();
    }
    const authorityStore = ChunkedSnapshotStore(
      maxChunkBytes: 4096,
      maxRowsPerChunk: 2,
      maxTotalRows: 100,
      maxTotalBytes: 65536,
    );
    final codec = SnapshotCodec();
    final source = ProbeDatabase(sourceFile);
    final container = Directory('${root.path}/roundtrip-container');
    try {
      await codec.captureChunked(
        source,
        container,
        store: authorityStore,
        pageSize: 1,
      );
    } finally {
      await source.close();
    }

    final stagedFile = File('${root.path}/roundtrip-staged.db');
    final checkpoints = <String>[];
    await codec.stageChunked(
      container,
      stagedFile,
      store: authorityStore,
      checkpoint: (table, rows) => checkpoints.add('$table:$rows'),
    );
    expect(stagedFile.existsSync(), isTrue);
    expect(checkpoints, containsAll(['events:1', 'events:2']));

    final restored = ProbeDatabase(stagedFile);
    final recaptured = Directory('${root.path}/roundtrip-recaptured');
    try {
      await codec.captureChunked(
        restored,
        recaptured,
        store: authorityStore,
        pageSize: 1,
      );
    } finally {
      await restored.close();
    }
    final originalFiles = container.listSync().whereType<File>().toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    final restoredFiles = recaptured.listSync().whereType<File>().toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    expect(restoredFiles.length, originalFiles.length);
    for (var index = 0; index < originalFiles.length; index++) {
      expect(
        restoredFiles[index].uri.pathSegments.last,
        originalFiles[index].uri.pathSegments.last,
      );
      expect(
        restoredFiles[index].readAsBytesSync(),
        originalFiles[index].readAsBytesSync(),
      );
    }
  });

  test('invalid chunk never leaves a staged database or sidecars', () async {
    final container = Directory('${root.path}/invalid-stage');
    final sourceFile = File('${root.path}/invalid-stage-source.db');
    final legacy = sqlite3.open(sourceFile.path);
    try {
      legacy.execute(
        File('../modular_persistence/test/fixtures/v1.sql').readAsStringSync(),
      );
    } finally {
      legacy.close();
    }
    const authorityStore = ChunkedSnapshotStore(
      maxChunkBytes: 4096,
      maxRowsPerChunk: 2,
      maxTotalRows: 100,
      maxTotalBytes: 65536,
    );
    final source = ProbeDatabase(sourceFile);
    try {
      await SnapshotCodec().captureChunked(
        source,
        container,
        store: authorityStore,
        pageSize: 1,
      );
    } finally {
      await source.close();
    }
    File('${container.path}/chunk-00000000.ndjson').writeAsStringSync('bad\n');
    final target = File('${root.path}/must-not-exist.db');
    await expectLater(
      SnapshotCodec().stageChunked(container, target, store: authorityStore),
      throwsA(isA<InvalidChunkedSnapshot>()),
    );
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      expect(File('${target.path}$suffix').existsSync(), isFalse);
    }
  });

  test('late chunk damage rolls back rows and removes the stage', () async {
    final sourceFile = File('${root.path}/late-damage-source.db');
    final legacy = sqlite3.open(sourceFile.path);
    try {
      legacy.execute(
        File('../modular_persistence/test/fixtures/v1.sql').readAsStringSync(),
      );
    } finally {
      legacy.close();
    }
    const authorityStore = ChunkedSnapshotStore(
      maxChunkBytes: 4096,
      maxRowsPerChunk: 1,
      maxTotalRows: 100,
      maxTotalBytes: 65536,
    );
    final container = Directory('${root.path}/late-damage-container');
    final source = ProbeDatabase(sourceFile);
    try {
      await SnapshotCodec().captureChunked(
        source,
        container,
        store: authorityStore,
        pageSize: 1,
      );
    } finally {
      await source.close();
    }

    final target = File('${root.path}/late-damage-stage.db');
    var damaged = false;
    await expectLater(
      SnapshotCodec().stageChunked(
        container,
        target,
        store: authorityStore,
        checkpoint: (_, _) {
          if (damaged) return;
          damaged = true;
          File('${container.path}/chunk-00000001.ndjson')
              .writeAsStringSync('late damage\n');
        },
      ),
      throwsA(isA<InvalidChunkedSnapshot>()),
    );
    expect(damaged, isTrue);
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      expect(File('${target.path}$suffix').existsSync(), isFalse);
    }
  });
}
