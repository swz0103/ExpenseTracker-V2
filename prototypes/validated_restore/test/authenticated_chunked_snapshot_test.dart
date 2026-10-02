import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/authenticated_chunked_snapshot.dart';
import 'package:validated_restore_probe/chunked_snapshot.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  const password = 'fixture passphrase only';
  const tables = ['accounts', 'events'];
  late Directory root;
  late Directory plain;
  late Directory authenticated;
  late CreatedAuthenticatedChunkedSnapshot created;
  const plainStore = ChunkedSnapshotStore(
    maxChunkBytes: 160,
    maxRowsPerChunk: 1,
    maxTotalRows: 20,
    maxTotalBytes: 2000,
  );
  const authenticatedStore = AuthenticatedChunkedSnapshotStore(
    plainStore: plainStore,
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('authenticated-chunks-');
    plain = Directory('${root.path}/plain');
    await plainStore.write(
      target: plain,
      schema: 24,
      tables: {
        'accounts': Stream.value({'id': 'a', 'name': 'Account'}),
        'events': Stream.fromIterable([
          {'amount': '10', 'id': 'e1'},
          {'amount': '-3', 'id': 'e2'},
        ]),
      },
    );
    authenticated = Directory('${root.path}/authenticated');
    created = await authenticatedStore.seal(
      source: plain,
      target: authenticated,
      expectedTables: tables,
      password: password,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('password and recovery recreate the exact bounded container', () async {
    final passwordTarget = Directory('${root.path}/password-open');
    final recoveryTarget = Directory('${root.path}/recovery-open');
    expect(
      (await authenticatedStore.openWithPassword(
        source: authenticated,
        target: passwordTarget,
        expectedTables: tables,
        password: password,
      )).totalRows,
      created.summary.totalRows,
    );
    await authenticatedStore.openWithRecovery(
      source: authenticated,
      target: recoveryTarget,
      expectedTables: tables,
      recoveryKey: created.recoveryKey,
    );
    for (final source in plain.listSync().whereType<File>()) {
      final name = source.uri.pathSegments.last;
      expect(
        File('${passwordTarget.path}/$name').readAsBytesSync(),
        source.readAsBytesSync(),
      );
      expect(
        File('${recoveryTarget.path}/$name').readAsBytesSync(),
        source.readAsBytesSync(),
      );
    }
  });

  test('encrypted chunk tampering leaves no plaintext target', () async {
    final chunk = File('${authenticated.path}/chunk-00000001.etv2');
    final envelope =
        jsonDecode(chunk.readAsStringSync()) as Map<String, dynamic>;
    final cipherText = base64Url.decode(envelope['cipherText'] as String);
    cipherText[0] ^= 1;
    envelope['cipherText'] = base64UrlEncode(cipherText);
    chunk.writeAsStringSync(jsonEncode(envelope), flush: true);
    final target = Directory('${root.path}/tampered-open');
    await expectLater(
      authenticatedStore.openWithPassword(
        source: authenticated,
        target: target,
        expectedTables: tables,
        password: password,
      ),
      throwsA(
        isA<BackupException>().having(
          (error) => error.code,
          'code',
          BackupError.authenticationFailed,
        ),
      ),
    );
    expect(target.existsSync(), isFalse);
    expect(
      root.listSync().where((entity) => entity.path.contains('tampered-open')),
      isEmpty,
    );
  });

  test('chunk swapping is rejected because purpose is authenticated', () async {
    final first = File('${authenticated.path}/chunk-00000000.etv2');
    final second = File('${authenticated.path}/chunk-00000001.etv2');
    final firstBytes = first.readAsBytesSync();
    first.writeAsBytesSync(second.readAsBytesSync(), flush: true);
    second.writeAsBytesSync(firstBytes, flush: true);
    final target = Directory('${root.path}/swapped-open');
    await expectLater(
      authenticatedStore.openWithRecovery(
        source: authenticated,
        target: target,
        expectedTables: tables,
        recoveryKey: created.recoveryKey,
      ),
      throwsA(isA<BackupException>()),
    );
    expect(target.existsSync(), isFalse);
  });

  test(
    'authenticated rows stage directly without a plaintext container',
    () async {
      final sourceFile = File('${root.path}/direct-source.db');
      final legacy = sqlite3.open(sourceFile.path);
      try {
        legacy.execute(
          File('../modular_persistence/test/fixtures/v1.sql')
              .readAsStringSync(),
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
      const secureStore = AuthenticatedChunkedSnapshotStore(
        plainStore: authorityStore,
      );
      final codec = SnapshotCodec();
      final encrypted = Directory('${root.path}/direct-encrypted');
      final source = ProbeDatabase(sourceFile);
      try {
        await codec.captureAuthenticatedChunked(
          source,
          encrypted,
          store: secureStore,
          password: password,
          pageSize: 1,
        );
      } finally {
        await source.close();
      }
      expect(
        encrypted.listSync().map((entity) => entity.uri.pathSegments.last),
        everyElement(anyOf(equals('metadata.json'), endsWith('.etv2'))),
      );

      final authority = Directory('${root.path}/test-only-reference');
      final referenceSource = ProbeDatabase(sourceFile);
      try {
        await codec.captureChunked(
          referenceSource,
          authority,
          store: authorityStore,
          pageSize: 1,
        );
      } finally {
        await referenceSource.close();
      }
      final opened = await secureStore.readWithPassword(
        source: encrypted,
        expectedTables: const [
          'accounts',
          'events',
          'legs',
          'openings',
          'allocations',
          'receipts',
          'audit',
        ],
        password: password,
      );
      final stagedFile = File('${root.path}/direct-stage.db');
      await codec.stageAuthenticatedChunked(opened, stagedFile);
      expect(stagedFile.existsSync(), isTrue);

      final staged = ProbeDatabase(stagedFile);
      final recaptured = Directory('${root.path}/direct-recaptured');
      try {
        await codec.captureChunked(
          staged,
          recaptured,
          store: authorityStore,
          pageSize: 1,
        );
      } finally {
        await staged.close();
      }
      final originalFiles = authority.listSync().whereType<File>().toList()
        ..sort((left, right) => left.path.compareTo(right.path));
      final restoredFiles = recaptured.listSync().whereType<File>().toList()
        ..sort((left, right) => left.path.compareTo(right.path));
      expect(restoredFiles.length, originalFiles.length);
      for (var index = 0; index < originalFiles.length; index++) {
        expect(
          restoredFiles[index].readAsBytesSync(),
          originalFiles[index].readAsBytesSync(),
        );
      }

      final lateOpened = await secureStore.readWithPassword(
        source: encrypted,
        expectedTables: const [
          'accounts',
          'events',
          'legs',
          'openings',
          'allocations',
          'receipts',
          'audit',
        ],
        password: password,
      );
      final target = File('${root.path}/late-secure-stage.db');
      var damaged = false;
      await expectLater(
        SnapshotCodec().stageAuthenticatedChunked(
          lateOpened,
          target,
          checkpoint: (_, _) {
            if (damaged) return;
            damaged = true;
            File('${encrypted.path}/chunk-00000001.etv2')
                .writeAsStringSync('late damage', flush: true);
          },
        ),
        throwsA(isA<BackupException>()),
      );
      expect(damaged, isTrue);
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        expect(File('${target.path}$suffix').existsSync(), isFalse);
      }
    },
  );
}
