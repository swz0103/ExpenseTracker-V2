import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:cloud_backup_probe/cloud_backup.dart';
import 'package:cloud_backup_probe/cloud_backup_work.dart';
import 'package:cloud_backup_probe/google_drive_adapter.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:persistent_jobs_probe/persistent_jobs.dart';
import 'package:test/test.dart';

void main() {
  final start = DateTime.utc(2026, 9, 30, 18);
  const password = 'correct horse battery staple';
  late Directory root;
  late StorageKey workKey;
  late StorageKey jobKey;
  late CloudBackupWorkStore work;
  late PersistentJobStore jobs;
  late _DriveApi api;
  late VerifiedBackupArtifact artifact;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('cloud-backup-work-');
    workKey = StorageKey.random();
    jobKey = StorageKey.random();
    work = _openWork(root, workKey);
    jobs = PersistentJobStore.open(File('${root.path}/jobs.db'), jobKey);
    api = _DriveApi();
    final created = await EnvelopeCodec().create(
      utf8.encode('{"snapshot":"durable"}'),
      password: password,
    );
    artifact = await VerifiedBackupArtifact.verify(
      backupId: 'durable-1',
      envelope: created.envelope,
      password: password,
      recoveryKey: created.recoveryKey,
      createdAt: start,
    );
  });

  tearDown(() {
    work.close();
    jobs.close();
    root.deleteSync(recursive: true);
  });

  test('staged envelope, reservation and job survive restart', () async {
    var runner = _runner(jobs: jobs, work: work, api: api);
    await runner.schedule(artifact, now: start);
    expect(work.byId(artifact.backupId)!.state, CloudBackupWorkState.staged);
    expect(
      jobs.byKey('cloud-backup:${artifact.backupId}')!.state,
      JobState.queued,
    );
    expect(
      File('${root.path}/artifacts/${artifact.backupId}.envelope').existsSync(),
      isTrue,
    );

    work.close();
    jobs.close();
    expect(
      () => _openWork(root, StorageKey.random()),
      throwsA(isA<EncryptedStorageUnavailable>()),
    );
    work = _openWork(root, workKey);
    jobs = PersistentJobStore.open(File('${root.path}/jobs.db'), jobKey);
    runner = _runner(jobs: jobs, work: work, api: api);
    expect(await runner.runNext(start), isTrue);
    expect(work.byId(artifact.backupId)!.state, CloudBackupWorkState.uploaded);
    expect(
      jobs.byKey('cloud-backup:${artifact.backupId}')!.state,
      JobState.succeeded,
    );
  });

  test(
    'reconcile enqueues work staged before a process interruption',
    () async {
      await work.stage(
        artifact,
        providerId: googleDriveBackupProviderId,
        now: start,
      );
      expect(jobs.byKey('cloud-backup:${artifact.backupId}'), isNull);
      _runner(jobs: jobs, work: work, api: api).reconcile(start);
      expect(
        jobs.byKey('cloud-backup:${artifact.backupId}')!.state,
        JobState.queued,
      );
    },
  );

  test('crash after remote commit retries the same Drive object', () async {
    final crashing = _runner(
      jobs: jobs,
      work: work,
      api: api,
      checkpoint: (point) {
        if (point == 'after-upload') throw StateError('simulated crash');
      },
    );
    await crashing.schedule(artifact, now: start);
    await expectLater(crashing.runNext(start), throwsStateError);
    expect(api.createCalls, 1);
    expect(
      jobs.byKey('cloud-backup:${artifact.backupId}')!.state,
      JobState.retryableFailure,
    );

    final retryAt = start.add(const Duration(seconds: 30));
    expect(
      await _runner(jobs: jobs, work: work, api: api).runNext(retryAt),
      isTrue,
    );
    expect(api.createCalls, 1);
    expect(work.byId(artifact.backupId)!.state, CloudBackupWorkState.uploaded);
  });

  test('tampered staged envelope is rejected before provider upload', () async {
    final runner = _runner(jobs: jobs, work: work, api: api);
    await runner.schedule(artifact, now: start);
    File('${root.path}/artifacts/${artifact.backupId}.envelope')
        .writeAsStringSync('tampered', flush: true);
    await expectLater(
      runner.runNext(start),
      throwsA(isA<CloudBackupValidationException>()),
    );
    expect(api.createCalls, 0);
    expect(
      jobs.byKey('cloud-backup:${artifact.backupId}')!.state,
      JobState.retryableFailure,
    );
  });

  test('same backup ID cannot be restaged with different content', () async {
    await work.stage(
      artifact,
      providerId: googleDriveBackupProviderId,
      now: start,
    );
    final other = await EnvelopeCodec().create(
      utf8.encode('{"snapshot":"different"}'),
      password: password,
    );
    final conflicting = await VerifiedBackupArtifact.verify(
      backupId: artifact.backupId,
      envelope: other.envelope,
      password: password,
      recoveryKey: other.recoveryKey,
      createdAt: start,
    );
    await expectLater(
      work.stage(
        conflicting,
        providerId: googleDriveBackupProviderId,
        now: start,
      ),
      throwsStateError,
    );
  });
}

CloudBackupWorkStore _openWork(Directory root, StorageKey key) =>
    CloudBackupWorkStore.open(
      databaseFile: File('${root.path}/work.db'),
      artifactDirectory: Directory('${root.path}/artifacts'),
      key: key,
    );

CloudBackupJobRunner _runner({
  required PersistentJobStore jobs,
  required CloudBackupWorkStore work,
  required _DriveApi api,
  void Function(String)? checkpoint,
}) {
  final provider = GoogleDriveBackupProvider(api: api, reservations: work);
  return CloudBackupJobRunner(
    jobs: jobs,
    work: work,
    provider: provider,
    checkpoint: checkpoint,
  );
}

final class _DriveApi implements DriveBackupApi {
  final _files = <String, DriveFileRecord>{};
  final _bytes = <String, List<int>>{};
  var generated = 0;
  var createCalls = 0;

  @override
  Future<String> generateFileId() async => 'drive_${++generated}';

  @override
  Future<DriveFileRecord?> getFile(String fileId) async => _files[fileId];

  @override
  Future<DriveFileRecord> createFile({
    required String fileId,
    required String name,
    required String mimeType,
    required List<int> bytes,
    required Map<String, String> appProperties,
  }) async {
    createCalls++;
    final record = DriveFileRecord(
      id: fileId,
      mimeType: mimeType,
      byteLength: bytes.length,
      appProperties: appProperties,
      trashed: false,
    );
    _files[fileId] = record;
    _bytes[fileId] = List<int>.from(bytes);
    return record;
  }

  @override
  Future<List<int>> downloadFile(String fileId) async =>
      List<int>.from(_bytes[fileId]!);

  @override
  Future<List<DriveFileRecord>> listBackupFiles() async =>
      _files.values.toList(growable: false);

  @override
  Future<void> deleteFile(String fileId) async {
    _files.remove(fileId);
    _bytes.remove(fileId);
  }
}
