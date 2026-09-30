import 'dart:convert';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:cloud_backup_probe/cloud_backup.dart';
import 'package:cloud_backup_probe/google_drive_adapter.dart';
import 'package:test/test.dart';

void main() {
  const password = 'correct horse battery staple';
  final createdAt = DateTime.utc(2026, 9, 30, 15);
  late String recoveryKey;
  late VerifiedBackupArtifact artifact;

  setUp(() async {
    final created = await EnvelopeCodec().create(
      utf8.encode('{"snapshot":"drive"}'),
      password: password,
    );
    recoveryKey = created.recoveryKey;
    artifact = await VerifiedBackupArtifact.verify(
      backupId: 'backup-drive-1',
      envelope: created.envelope,
      password: password,
      recoveryKey: recoveryKey,
      createdAt: createdAt,
    );
  });

  test('generated Drive ID survives adapter recreation', () async {
    final api = _DriveApi();
    final reservations = _Reservations();
    final first = await GoogleDriveBackupProvider(
      api: api,
      reservations: reservations,
    ).reserve(artifact);
    final second = await GoogleDriveBackupProvider(
      api: api,
      reservations: reservations,
    ).reserve(artifact);
    expect(second.objectId, first.objectId);
    expect(api.generateCalls, 1);
  });

  test(
    'upload uses pre-generated ID and private integrity properties',
    () async {
      final api = _DriveApi();
      final provider = GoogleDriveBackupProvider(
        api: api,
        reservations: _Reservations(),
      );
      final coordinator = CloudBackupCoordinator(provider);
      final uploaded = await coordinator.upload(artifact);
      expect(uploaded.sha256, artifact.sha256);
      expect(api.lastCreateId, uploaded.objectId);
      expect(api.lastCreateName, contains(artifact.backupId));
      expect(api.lastCreateProperties, {
        'format': 'ExpenseTracker-V2-backup',
        'formatVersion': '1',
        'backupId': artifact.backupId,
        'sha256': artifact.sha256,
        'byteLength': artifact.byteLength.toString(),
        'createdAt': artifact.createdAt.toIso8601String(),
      });
      expect(
        await coordinator.downloadAndVerify(
          uploaded,
          password: password,
          recoveryKey: recoveryKey,
        ),
        artifact.envelope,
      );
    },
  );

  test(
    'Drive conflict after commit is recovered by metadata inspection',
    () async {
      final api = _DriveApi(conflictAfterCommit: true);
      final coordinator = CloudBackupCoordinator(
        GoogleDriveBackupProvider(api: api, reservations: _Reservations()),
      );
      final result = await coordinator.upload(artifact);
      expect(result.backupId, artifact.backupId);
      expect(api.createCalls, 1);
      expect(api.getCalls, 2);
    },
  );

  test('Drive auth, quota and throttling retain distinct meanings', () async {
    final cases = {
      DriveApiFailure.authenticationRequired:
          CloudBackupProviderFailure.authenticationRequired,
      DriveApiFailure.quotaExceeded: CloudBackupProviderFailure.quotaExceeded,
      DriveApiFailure.throttled: CloudBackupProviderFailure.throttled,
    };
    for (final entry in cases.entries) {
      final coordinator = CloudBackupCoordinator(
        GoogleDriveBackupProvider(
          api: _DriveApi(createFailure: entry.key),
          reservations: _Reservations(),
        ),
      );
      await expectLater(
        coordinator.upload(artifact),
        throwsA(
          isA<CloudBackupProviderException>().having(
            (error) => error.failure,
            'failure',
            entry.value,
          ),
        ),
      );
    }
  });

  test('trashed and malformed Drive files are never accepted', () async {
    final trashed = _DriveApi(trashedAfterCreate: true);
    final trashedCoordinator = CloudBackupCoordinator(
      GoogleDriveBackupProvider(api: trashed, reservations: _Reservations()),
    );
    await trashedCoordinator.upload(artifact);
    await expectLater(
      trashedCoordinator.upload(artifact),
      throwsA(
        isA<CloudBackupProviderException>().having(
          (error) => error.failure,
          'failure',
          CloudBackupProviderFailure.unavailable,
        ),
      ),
    );

    final malformed = _DriveApi(omitIntegrityProperty: true);
    await expectLater(
      CloudBackupCoordinator(
        GoogleDriveBackupProvider(
          api: malformed,
          reservations: _Reservations(),
        ),
      ).upload(artifact),
      throwsA(isA<CloudBackupValidationException>()),
    );
  });
}

final class _Reservations implements DriveReservationStore {
  final _objects = <String, String>{};

  @override
  Future<String?> objectIdFor(String backupId) async => _objects[backupId];

  @override
  Future<void> save({
    required String backupId,
    required String objectId,
  }) async {
    final existing = _objects[backupId];
    if (existing != null && existing != objectId) {
      throw StateError('reservation conflict');
    }
    _objects[backupId] = objectId;
  }
}

final class _DriveApi implements DriveBackupApi {
  _DriveApi({
    this.conflictAfterCommit = false,
    this.trashedAfterCreate = false,
    this.omitIntegrityProperty = false,
    this.createFailure,
  });

  final bool conflictAfterCommit;
  final bool trashedAfterCreate;
  final bool omitIntegrityProperty;
  final DriveApiFailure? createFailure;
  final _files = <String, DriveFileRecord>{};
  final _bytes = <String, List<int>>{};
  var generateCalls = 0;
  var createCalls = 0;
  var getCalls = 0;
  String? lastCreateId;
  String? lastCreateName;
  Map<String, String>? lastCreateProperties;

  @override
  Future<String> generateFileId() async {
    generateCalls++;
    return 'generated_$generateCalls';
  }

  @override
  Future<DriveFileRecord?> getFile(String fileId) async {
    getCalls++;
    return _files[fileId];
  }

  @override
  Future<DriveFileRecord> createFile({
    required String fileId,
    required String name,
    required String mimeType,
    required List<int> bytes,
    required Map<String, String> appProperties,
  }) async {
    createCalls++;
    lastCreateId = fileId;
    lastCreateName = name;
    lastCreateProperties = Map<String, String>.from(appProperties);
    if (createFailure != null) throw DriveApiException(createFailure!);
    final properties = Map<String, String>.from(appProperties);
    if (omitIntegrityProperty) properties.remove('sha256');
    final record = DriveFileRecord(
      id: fileId,
      mimeType: mimeType,
      byteLength: bytes.length,
      appProperties: properties,
      trashed: trashedAfterCreate,
    );
    _files[fileId] = record;
    _bytes[fileId] = List<int>.from(bytes);
    if (conflictAfterCommit && createCalls == 1) {
      throw const DriveApiException(DriveApiFailure.conflict);
    }
    return record;
  }

  @override
  Future<List<int>> downloadFile(String fileId) async =>
      List<int>.from(_bytes[fileId]!);
}
