import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/authenticated_chunked_snapshot.dart';
import 'package:validated_restore_probe/chunked_snapshot.dart';

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
}
