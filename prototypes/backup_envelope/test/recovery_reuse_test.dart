import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

void main() {
  const password = 'synthetic-original-password';
  const nextPassword = 'synthetic-next-password';
  final originalBytes = utf8.encode('first synthetic snapshot');
  final nextBytes = utf8.encode('second synthetic snapshot');
  late CreatedBackup original;
  late CreatedBackup next;
  setUpAll(() async {
    original = await EnvelopeCodec().create(originalBytes, password: password);
    next = await EnvelopeCodec().create(
      nextBytes,
      password: nextPassword,
      recoveryKey: original.recoveryKey,
    );
  });
  Matcher failure(BackupError code) =>
      throwsA(isA<BackupException>().having((e) => e.code, 'code', code));

  test('caller mutation during credential validation cannot change captured payload', () async {
    final input = List<int>.from(nextBytes);
    final pending = EnvelopeCodec().create(
      input,
      password: nextPassword,
      recoveryKey: original.recoveryKey,
    );
    input
      ..clear()
      ..add(999);
    final created = await pending;
    expect(
      await EnvelopeCodec().openWithRecovery(
        created.envelope,
        original.recoveryKey,
      ),
      nextBytes,
    );
  });

  test(
    'explicit recovery credential opens old and new backups with fresh codecs',
    () async {
      expect(next.recoveryKey == original.recoveryKey, isTrue);
      expect(
        await EnvelopeCodec().openWithRecovery(
          original.envelope,
          original.recoveryKey,
        ),
        originalBytes,
      );
      expect(
        await EnvelopeCodec().openWithRecovery(
          next.envelope,
          original.recoveryKey,
        ),
        nextBytes,
      );
      expect(next.envelope.contains(original.recoveryKey), isFalse);
      final header = (jsonDecode(next.envelope) as Map)['header'] as Map;
      expect(header['version'], 1);
      expect(header.keys.toSet(), {
        'format',
        'version',
        'cipher',
        'kdf',
        'salt',
        'payloadNonce',
        'passwordNonce',
        'recoveryNonce',
      });
    },
  );
  test('password change applies only to new backup and recovery remains independent', () async {
    expect(
      await EnvelopeCodec().openWithPassword(original.envelope, password),
      originalBytes,
    );
    expect(
      await EnvelopeCodec().openWithPassword(next.envelope, nextPassword),
      nextBytes,
    );
    await expectLater(
      EnvelopeCodec().openWithPassword(original.envelope, nextPassword),
      failure(BackupError.authenticationFailed),
    );
    await expectLater(
      EnvelopeCodec().openWithPassword(next.envelope, password),
      failure(BackupError.authenticationFailed),
    );
  });
  test(
    'reuse still produces fresh salt, nonces and wrapped data keys',
    () async {
      final another = await EnvelopeCodec().create(
        nextBytes,
        password: nextPassword,
        recoveryKey: original.recoveryKey,
      );
      final a = jsonDecode(next.envelope) as Map;
      final b = jsonDecode(another.envelope) as Map;
      for (final field in [
        'salt',
        'payloadNonce',
        'passwordNonce',
        'recoveryNonce',
      ]) {
        expect(a['header'][field] == b['header'][field], isFalse);
      }
      for (final slot in ['passwordBox', 'recoveryBox', 'payloadBox']) {
        expect(a[slot]['cipherText'] == b[slot]['cipherText'], isFalse);
      }
      Future<List<int>> dataKey(Map map) {
        final header = map['header'] as Map;
        final box = map['recoveryBox'] as Map;
        final recoveryBytes = base64Url
            .decode(original.recoveryKey.substring('ETV2-R1-'.length))
            .sublist(0, 32);
        return AesGcm.with256bits().decrypt(
          SecretBox(
            base64Url.decode(box['cipherText'] as String),
            nonce: base64Url.decode(header['recoveryNonce'] as String),
            mac: Mac(base64Url.decode(box['mac'] as String)),
          ),
          secretKey: SecretKey(recoveryBytes),
          aad: utf8.encode(jsonEncode([header, 'recovery'])),
        );
      }

      // Different ciphertext alone would not prove independent data keys.
      expect(
        base64UrlEncode(await dataKey(a)) == base64UrlEncode(await dataKey(b)),
        isFalse,
      );
      expect(
        await EnvelopeCodec().openWithRecovery(
          another.envelope,
          original.recoveryKey,
        ),
        nextBytes,
      );
    },
  );
  test('invalid saved credential is rejected rather than replaced', () async {
    final corrupted = base64Url.decode(
      original.recoveryKey.substring('ETV2-R1-'.length),
    );
    corrupted[35] ^= 1;
    for (final bad in [
      '',
      'ETV2-R2-future',
      'ETV2-R1-short',
      'ETV2-R1-${base64UrlEncode(corrupted)}',
    ]) {
      await expectLater(
        EnvelopeCodec().create(
          nextBytes,
          password: nextPassword,
          recoveryKey: bad,
        ),
        failure(BackupError.invalidFormat),
      );
    }
    expect(
      await EnvelopeCodec().openWithRecovery(
        original.envelope,
        original.recoveryKey,
      ),
      originalBytes,
    );
  });
  test(
    'cross-backup recovery box substitution fails with the same recovery key',
    () async {
      final forged = jsonDecode(next.envelope) as Map<String, dynamic>;
      forged['recoveryBox'] =
          (jsonDecode(original.envelope) as Map)['recoveryBox'];
      await expectLater(
        EnvelopeCodec().openWithRecovery(
          jsonEncode(forged),
          original.recoveryKey,
        ),
        failure(BackupError.authenticationFailed),
      );
    },
  );
  test(
    'new backup is restored in separate processes with one credential each',
    () async {
      final root = Directory('.dart_tool/reused-recovery')
        ..createSync(recursive: true);
      final work = root.createTempSync('case-');
      try {
        final file = File('${work.path}/backup.json')
          ..writeAsStringSync(next.envelope);
        for (final entry in {
          'password': nextPassword,
          'recovery': original.recoveryKey,
        }.entries) {
          final credential = File('${work.path}/${entry.key}.txt')
            ..writeAsStringSync(entry.value);
          final output = File('${work.path}/${entry.key}.restored');
          final result = await Process.run(Platform.resolvedExecutable, [
            'run',
            'bin/restore_probe.dart',
            entry.key,
            file.absolute.path,
            credential.absolute.path,
            output.absolute.path,
          ]);
          expect(result.exitCode, 0);
          expect(output.readAsBytesSync(), nextBytes);
        }
      } finally {
        if (!work.resolveSymbolicLinksSync().startsWith(
          '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
        )) {
          throw StateError('Unsafe fixture cleanup');
        }
        work.deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
