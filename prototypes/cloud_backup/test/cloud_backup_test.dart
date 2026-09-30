import 'dart:convert';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:cloud_backup_probe/cloud_backup.dart';
import 'package:test/test.dart';

void main() {
  const password = 'correct horse battery staple';
  final createdAt = DateTime.utc(2026, 9, 30, 12);
  late String recoveryKey;
  late VerifiedBackupArtifact artifact;

  setUp(() async {
    final created = await EnvelopeCodec().create(
      utf8.encode('{"snapshot":"verified"}'),
      password: password,
    );
    recoveryKey = created.recoveryKey;
    artifact = await VerifiedBackupArtifact.verify(
      backupId: 'backup-0001',
      envelope: created.envelope,
      password: password,
      recoveryKey: recoveryKey,
      createdAt: createdAt,
    );
  });

  test('artifact requires both independent credentials', () async {
    await expectLater(
      VerifiedBackupArtifact.verify(
        backupId: 'backup-0001',
        envelope: artifact.envelope,
        password: password,
        recoveryKey: 'invalid',
        createdAt: createdAt,
      ),
      throwsA(
        isA<CloudBackupValidationException>().having(
          (error) => error.failure,
          'failure',
          CloudBackupValidationFailure.invalidArtifact,
        ),
      ),
    );
  });

  test('same backup ID reserves and uploads one immutable object', () async {
    final provider = _MemoryProvider();
    final coordinator = CloudBackupCoordinator(provider);
    final first = await coordinator.upload(artifact);
    final second = await coordinator.upload(artifact);
    expect(second.objectId, first.objectId);
    expect(provider.reserveCalls, 2);
    expect(provider.uploadCalls, 1);
    expect(provider.objectCount, 1);
  });

  test(
    'commit without response is recovered by inspecting reservation',
    () async {
      final provider = _MemoryProvider(loseFirstUploadResponse: true);
      final uploaded = await CloudBackupCoordinator(provider).upload(artifact);
      expect(uploaded.backupId, artifact.backupId);
      expect(provider.uploadCalls, 1);
      expect(provider.inspectCalls, 2);
    },
  );

  test('existing remote object with different content is rejected', () async {
    final provider = _MemoryProvider();
    final reservation = await provider.reserve(artifact);
    provider.putMetadata(
      reservation,
      RemoteBackupMetadata(
        providerId: provider.providerId,
        objectId: reservation.objectId,
        backupId: artifact.backupId,
        sha256: '0' * 64,
        byteLength: artifact.byteLength,
        createdAt: artifact.createdAt,
        contentType: cloudBackupContentType,
      ),
      utf8.encode(artifact.envelope),
    );
    await expectLater(
      CloudBackupCoordinator(provider).upload(artifact),
      throwsA(
        isA<CloudBackupValidationException>().having(
          (error) => error.failure,
          'failure',
          CloudBackupValidationFailure.remoteMetadataMismatch,
        ),
      ),
    );
    expect(provider.uploadCalls, 0);
  });

  test('download verifies digest and both unlock paths', () async {
    final provider = _MemoryProvider();
    final coordinator = CloudBackupCoordinator(provider);
    final metadata = await coordinator.upload(artifact);
    expect(
      await coordinator.downloadAndVerify(
        metadata,
        password: password,
        recoveryKey: recoveryKey,
      ),
      artifact.envelope,
    );
    provider.corrupt(metadata.objectId);
    await expectLater(
      coordinator.downloadAndVerify(
        metadata,
        password: password,
        recoveryKey: recoveryKey,
      ),
      throwsA(
        isA<CloudBackupValidationException>().having(
          (error) => error.failure,
          'failure',
          CloudBackupValidationFailure.corruptDownload,
        ),
      ),
    );
  });

  test('authentication and quota errors remain distinct', () async {
    for (final failure in [
      CloudBackupProviderFailure.authenticationRequired,
      CloudBackupProviderFailure.quotaExceeded,
    ]) {
      final provider = _MemoryProvider(uploadFailure: failure);
      await expectLater(
        CloudBackupCoordinator(provider).upload(artifact),
        throwsA(
          isA<CloudBackupProviderException>().having(
            (error) => error.failure,
            'failure',
            failure,
          ),
        ),
      );
    }
  });
}

final class _MemoryProvider implements CloudBackupProvider {
  _MemoryProvider({this.loseFirstUploadResponse = false, this.uploadFailure});

  @override
  String get providerId => 'memory-provider';

  final bool loseFirstUploadResponse;
  final CloudBackupProviderFailure? uploadFailure;
  final Map<String, RemoteBackupReservation> _reservations = {};
  final Map<String, RemoteBackupMetadata> _metadata = {};
  final Map<String, List<int>> _objects = {};
  var reserveCalls = 0;
  var inspectCalls = 0;
  var uploadCalls = 0;

  int get objectCount => _objects.length;

  @override
  Future<RemoteBackupReservation> reserve(
    VerifiedBackupArtifact artifact,
  ) async {
    reserveCalls++;
    return _reservations.putIfAbsent(
      artifact.backupId,
      () => RemoteBackupReservation(
        providerId: providerId,
        objectId: 'object-${artifact.backupId}',
        backupId: artifact.backupId,
      ),
    );
  }

  @override
  Future<RemoteBackupMetadata?> inspect(
    RemoteBackupReservation reservation,
  ) async {
    inspectCalls++;
    return _metadata[reservation.objectId];
  }

  @override
  Future<RemoteBackupMetadata> upload(
    RemoteBackupReservation reservation,
    VerifiedBackupArtifact artifact,
  ) async {
    uploadCalls++;
    if (uploadFailure != null) {
      throw CloudBackupProviderException(uploadFailure!);
    }
    final metadata = RemoteBackupMetadata(
      providerId: providerId,
      objectId: reservation.objectId,
      backupId: artifact.backupId,
      sha256: artifact.sha256,
      byteLength: artifact.byteLength,
      createdAt: artifact.createdAt,
      contentType: cloudBackupContentType,
    );
    putMetadata(reservation, metadata, utf8.encode(artifact.envelope));
    if (loseFirstUploadResponse && uploadCalls == 1) {
      throw const CloudBackupProviderException(
        CloudBackupProviderFailure.uncertainResult,
      );
    }
    return metadata;
  }

  void putMetadata(
    RemoteBackupReservation reservation,
    RemoteBackupMetadata metadata,
    List<int> bytes,
  ) {
    _metadata[reservation.objectId] = metadata;
    _objects[reservation.objectId] = List<int>.from(bytes);
  }

  void corrupt(String objectId) {
    _objects[objectId] = [..._objects[objectId]!, 0];
  }

  @override
  Future<List<int>> download(String objectId) async =>
      List<int>.from(_objects[objectId]!);
}
