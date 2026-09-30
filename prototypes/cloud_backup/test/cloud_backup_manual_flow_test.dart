import 'dart:convert';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:cloud_backup_probe/cloud_backup.dart';
import 'package:cloud_backup_probe/cloud_backup_history.dart';
import 'package:cloud_backup_probe/cloud_backup_manual_flow.dart';
import 'package:test/test.dart';

void main() {
  const password = 'correct horse battery staple';
  final createdAt = DateTime.utc(2026, 10, 1, 10);
  late CreatedBackup created;
  late _Provider provider;
  late List<VerifiedBackupArtifact> scheduled;
  late CloudBackupManualFlow flow;

  setUp(() async {
    created = await EnvelopeCodec().create(
      utf8.encode('{"snapshot":"manual-flow"}'),
      password: password,
    );
    provider = _Provider();
    scheduled = [];
    flow = CloudBackupManualFlow(
      providers: CloudBackupProviderRegistry([provider]),
      uploadTargets: [
        CloudBackupManualTarget(
          providerId: provider.providerId,
          schedule: (artifact, now) async {
            scheduled.add(artifact);
            await CloudBackupCoordinator(provider).upload(artifact);
          },
        ),
      ],
    );
  });

  test('manual backup verifies both credentials before scheduling', () async {
    final receipt = await flow.scheduleBackup(
      providerId: provider.providerId,
      backupId: 'manual-1',
      envelope: created.envelope,
      password: password,
      recoveryKey: created.recoveryKey,
      createdAt: createdAt,
      now: createdAt,
    );
    expect(receipt.state, ManualCloudBackupState.queued);
    expect(scheduled.single.backupId, 'manual-1');
    expect(
      (await flow.history(provider.providerId)).single.backupId,
      'manual-1',
    );

    await expectLater(
      flow.scheduleBackup(
        providerId: provider.providerId,
        backupId: 'manual-2',
        envelope: created.envelope,
        password: password,
        recoveryKey: 'wrong',
        createdAt: createdAt,
        now: createdAt,
      ),
      throwsA(isA<CloudBackupValidationException>()),
    );
    expect(scheduled, hasLength(1));
  });

  test(
    'download for restore accepts password or recovery independently',
    () async {
      await flow.scheduleBackup(
        providerId: provider.providerId,
        backupId: 'manual-1',
        envelope: created.envelope,
        password: password,
        recoveryKey: created.recoveryKey,
        createdAt: createdAt,
        now: createdAt,
      );
      final metadata = (await flow.history(provider.providerId)).single;
      expect(
        await flow.downloadForRestore(
          providerId: provider.providerId,
          backup: metadata,
          credentialKind: CloudBackupCredentialKind.password,
          credential: password,
        ),
        created.envelope,
      );
      expect(
        await flow.downloadForRestore(
          providerId: provider.providerId,
          backup: metadata,
          credentialKind: CloudBackupCredentialKind.recoveryKey,
          credential: created.recoveryKey,
        ),
        created.envelope,
      );
    },
  );
}

final class _Provider
    implements CloudBackupProvider, CloudBackupCatalogProvider {
  @override
  String get providerId => 'memory-provider';

  final _reservations = <String, RemoteBackupReservation>{};
  final _metadata = <String, RemoteBackupMetadata>{};
  final _bytes = <String, List<int>>{};

  @override
  Future<RemoteBackupReservation> reserve(
    VerifiedBackupArtifact artifact,
  ) async => _reservations.putIfAbsent(
    artifact.backupId,
    () => RemoteBackupReservation(
      providerId: providerId,
      objectId: 'object-${artifact.backupId}',
      backupId: artifact.backupId,
    ),
  );

  @override
  Future<RemoteBackupMetadata?> inspect(
    RemoteBackupReservation reservation,
  ) async => _metadata[reservation.objectId];

  @override
  Future<RemoteBackupMetadata> upload(
    RemoteBackupReservation reservation,
    VerifiedBackupArtifact artifact,
  ) async {
    final result = RemoteBackupMetadata(
      providerId: providerId,
      objectId: reservation.objectId,
      backupId: artifact.backupId,
      sha256: artifact.sha256,
      byteLength: artifact.byteLength,
      createdAt: artifact.createdAt,
      contentType: cloudBackupContentType,
    );
    _metadata[result.objectId] = result;
    _bytes[result.objectId] = utf8.encode(artifact.envelope);
    return result;
  }

  @override
  Future<List<int>> download(String objectId) async =>
      List.of(_bytes[objectId]!);

  @override
  Future<List<RemoteBackupMetadata>> listBackups() async =>
      _metadata.values.toList(growable: false);

  @override
  Future<void> deleteBackup(RemoteBackupMetadata expected) async {
    _metadata.remove(expected.objectId);
    _bytes.remove(expected.objectId);
  }
}
