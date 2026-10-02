import 'dart:convert';

import 'package:backup_envelope_probe/chunk_envelope.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:test/test.dart';

void main() {
  const password = 'fixture passphrase only';
  final manifest = utf8.encode('{"chunks":["chunk-00000000"]}');
  final chunk = utf8.encode('bounded financial rows');

  test(
    'one wrapped key authenticates manifest and chunks by purpose',
    () async {
      final created = await ChunkEnvelopeCodec().create(password: password);
      final manifestEnvelope = await created.session.seal(
        manifest,
        purpose: 'manifest',
      );
      final chunkEnvelope = await created.session.seal(
        chunk,
        purpose: 'chunk-00000000',
      );
      final passwordSession = await ChunkEnvelopeCodec().openWithPassword(
        created.metadata,
        password,
      );
      final recoverySession = await ChunkEnvelopeCodec().openWithRecovery(
        created.metadata,
        created.recoveryKey,
      );
      expect(
        await passwordSession.open(manifestEnvelope, purpose: 'manifest'),
        manifest,
      );
      expect(
        await recoverySession.open(chunkEnvelope, purpose: 'chunk-00000000'),
        chunk,
      );
    },
  );

  test('ciphertext, purpose swap and metadata tampering fail', () async {
    final created = await ChunkEnvelopeCodec().create(password: password);
    final envelope = await created.session.seal(
      chunk,
      purpose: 'chunk-00000000',
    );
    final session = await ChunkEnvelopeCodec().openWithPassword(
      created.metadata,
      password,
    );
    final damaged = jsonDecode(envelope) as Map<String, dynamic>;
    final cipherText = base64Url.decode(damaged['cipherText'] as String);
    cipherText[0] ^= 1;
    damaged['cipherText'] = base64UrlEncode(cipherText);
    await expectLater(
      session.open(jsonEncode(damaged), purpose: 'chunk-00000000'),
      throwsA(
        isA<BackupException>().having(
          (error) => error.code,
          'code',
          BackupError.authenticationFailed,
        ),
      ),
    );
    await expectLater(
      session.open(envelope, purpose: 'manifest'),
      throwsA(isA<BackupException>()),
    );

    final metadata = jsonDecode(created.metadata) as Map<String, dynamic>;
    metadata['header']['sessionId'] = base64UrlEncode(List.filled(16, 0));
    await expectLater(
      ChunkEnvelopeCodec().openWithRecovery(
        jsonEncode(metadata),
        created.recoveryKey,
      ),
      throwsA(
        isA<BackupException>().having(
          (error) => error.code,
          'code',
          BackupError.authenticationFailed,
        ),
      ),
    );
  });

  test('wrong credentials and invalid resource requests fail closed', () async {
    final created = await ChunkEnvelopeCodec().create(password: password);
    await expectLater(
      ChunkEnvelopeCodec().openWithPassword(
        created.metadata,
        'incorrect fixture password',
      ),
      throwsA(isA<BackupException>()),
    );
    await expectLater(
      created.session.seal(chunk, purpose: '../chunk'),
      throwsA(isA<BackupException>()),
    );
    await expectLater(
      created.session.seal(
        List.filled(ChunkEnvelopeCodec.maxChunkBytes + 1, 0),
        purpose: 'manifest',
      ),
      throwsA(isA<BackupException>()),
    );
  });

  test('legacy and chunked formats never accept each other', () async {
    final legacy = await EnvelopeCodec().create(chunk, password: password);
    final chunked = await ChunkEnvelopeCodec().create(password: password);
    await expectLater(
      ChunkEnvelopeCodec().openWithPassword(legacy.envelope, password),
      throwsA(isA<BackupException>()),
    );
    await expectLater(
      EnvelopeCodec().openWithPassword(chunked.metadata, password),
      throwsA(isA<BackupException>()),
    );
    await expectLater(
      ChunkEnvelopeCodec().openWithRecovery(
        chunked.metadata,
        legacy.recoveryKey,
      ),
      throwsA(
        isA<BackupException>().having(
          (error) => error.code,
          'code',
          BackupError.invalidFormat,
        ),
      ),
    );
    await expectLater(
      EnvelopeCodec().openWithRecovery(legacy.envelope, chunked.recoveryKey),
      throwsA(
        isA<BackupException>().having(
          (error) => error.code,
          'code',
          BackupError.invalidFormat,
        ),
      ),
    );
  });
}
