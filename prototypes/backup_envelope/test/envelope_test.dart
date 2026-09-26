import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:test/test.dart';

void main() {
  const password = 'fixture passphrase only';
  final bytes = utf8.encode(
    'Synthetic ledger payload: balance 115.00; receipt retained.',
  );
  late CreatedBackup backup;
  setUpAll(() async {
    backup = await EnvelopeCodec().create(bytes, password: password);
  });
  Matcher error(BackupError code) =>
      throwsA(isA<BackupException>().having((e) => e.code, 'code', code));
  String change(void Function(Map<String, dynamic>) modify) {
    final map = jsonDecode(backup.envelope) as Map<String, dynamic>;
    modify(map);
    return jsonEncode(map);
  }

  test('password and recovery separately recover identical bytes', () async {
    expect(
      await EnvelopeCodec().openWithPassword(backup.envelope, password),
      bytes,
    );
    expect(
      await EnvelopeCodec().openWithRecovery(
        backup.envelope,
        backup.recoveryKey,
      ),
      bytes,
    );
    expect(backup.envelope.contains(password), isFalse);
    expect(backup.envelope.contains(backup.recoveryKey), isFalse);
    expect(backup.envelope.contains('115.00'), isFalse);
  });
  test('wrapped key tampering and slot swapping fail authentication', () async {
    final tampered = change((map) {
      final mac = base64Url.decode(map['recoveryBox']['mac'] as String);
      mac[0] ^= 1;
      map['recoveryBox']['mac'] = base64UrlEncode(mac);
    });
    await expectLater(
      EnvelopeCodec().openWithRecovery(tampered, backup.recoveryKey),
      error(BackupError.authenticationFailed),
    );
    final swapped = change((map) {
      map['recoveryBox'] = map['passwordBox'];
    });
    await expectLater(
      EnvelopeCodec().openWithRecovery(swapped, backup.recoveryKey),
      error(BackupError.authenticationFailed),
    );
  });
  test('wrong password fails authentication', () async {
    await expectLater(
      EnvelopeCodec().openWithPassword(
        backup.envelope,
        'incorrect fixture password',
      ),
      error(BackupError.authenticationFailed),
    );
  });
  test('payload ciphertext and header tampering are rejected', () async {
    final damaged = change((map) {
      final raw = base64Url.decode(map['payloadBox']['cipherText'] as String);
      raw[0] ^= 1;
      map['payloadBox']['cipherText'] = base64UrlEncode(raw);
    });
    await expectLater(
      EnvelopeCodec().openWithRecovery(damaged, backup.recoveryKey),
      error(BackupError.authenticationFailed),
    );
    final metadata = change((map) {
      map['header']['salt'] = base64UrlEncode(List.filled(16, 0));
    });
    await expectLater(
      EnvelopeCodec().openWithRecovery(metadata, backup.recoveryKey),
      error(BackupError.authenticationFailed),
    );
  });
  test('wrong versions and unknown KDF policies rejected before expensive derivation', () async {
    for (final field in ['version', 'kdf']) {
      final invalid = change((map) {
        map['header'][field] = field == 'version' ? 99 : 'argon2-unbounded';
      });
      await expectLater(
        EnvelopeCodec().openWithPassword(invalid, password),
        error(BackupError.unsupportedVersion),
      );
    }
  });
  test(
    'truncated envelope and malformed key fail before returning payload',
    () async {
      await expectLater(
        EnvelopeCodec().openWithRecovery(
          backup.envelope.substring(0, 20),
          backup.recoveryKey,
        ),
        error(BackupError.invalidFormat),
      );
      await expectLater(
        EnvelopeCodec().openWithRecovery(backup.envelope, 'bad-key'),
        error(BackupError.invalidFormat),
      );
      final damagedKey = 'ETV2-R1-${base64UrlEncode(List.filled(36, 0))}';
      await expectLater(
        EnvelopeCodec().openWithRecovery(backup.envelope, damagedKey),
        error(BackupError.invalidFormat),
      );
    },
  );
  test('each new backup uses independent randomness', () async {
    final another = await EnvelopeCodec().create(bytes, password: password);
    expect(another.envelope, isNot(backup.envelope));
    expect(another.recoveryKey, isNot(backup.recoveryKey));
    await expectLater(
      EnvelopeCodec().openWithRecovery(backup.envelope, another.recoveryKey),
      error(BackupError.authenticationFailed),
    );
  });
  test('oversized input and short creation password are rejected', () async {
    await expectLater(
      EnvelopeCodec().create(
        List.filled(EnvelopeCodec.maxPayloadBytes + 1, 0),
        password: password,
      ),
      error(BackupError.limitExceeded),
    );
    await expectLater(
      EnvelopeCodec().create(bytes, password: 'short'),
      error(BackupError.invalidPassword),
    );
  });
  test(
    'two fresh child processes recover with only one credential each',
    () async {
      final root = Directory('.dart_tool/restore-fixtures')
        ..createSync(recursive: true);
      final fixture = root.createTempSync('clean-');
      try {
        final package = File('${fixture.path}/backup.json')
          ..writeAsStringSync(backup.envelope);
        for (final entry in {
          'password': password,
          'recovery': backup.recoveryKey,
        }.entries) {
          final credential = File('${fixture.path}/${entry.key}.txt')
            ..writeAsStringSync(entry.value);
          final output = File('${fixture.path}/${entry.key}.restored');
          final result = await Process.run(Platform.resolvedExecutable, [
            'run',
            'bin/restore_probe.dart',
            entry.key,
            package.absolute.path,
            credential.absolute.path,
            output.absolute.path,
          ]);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          expect(output.readAsBytesSync(), bytes);
        }
      } finally {
        if (!fixture.resolveSymbolicLinksSync().startsWith(
          '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
        ))
          throw StateError('Unsafe cleanup.');
        fixture.deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
