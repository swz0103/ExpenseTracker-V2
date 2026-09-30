import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:cloud_backup_probe/cloud_backup.dart';
import 'package:cloud_backup_probe/cloud_backup_schedule.dart';
import 'package:cloud_backup_probe/cloud_backup_work.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:persistent_jobs_probe/persistent_jobs.dart';
import 'package:test/test.dart';

void main() {
  final start = DateTime.utc(2026, 10, 1, 9);
  const password = 'correct horse battery staple';
  late Directory root;
  late StorageKey scheduleKey;
  late CloudBackupScheduleStore schedules;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cloud-backup-schedule-');
    scheduleKey = StorageKey.random();
    schedules = CloudBackupScheduleStore.open(
      File('${root.path}/schedules.db'),
      scheduleKey,
    );
  });

  tearDown(() {
    schedules.close();
    root.deleteSync(recursive: true);
  });

  test(
    'encrypted schedule survives restart and coalesces missed periods',
    () async {
      schedules.configure(
        providerId: 'provider-a',
        enabled: true,
        interval: const Duration(days: 1),
        firstDueAt: start,
        now: start,
      );
      final first = (await schedules.due(start)).single;
      schedules.close();
      expect(
        () => CloudBackupScheduleStore.open(
          File('${root.path}/schedules.db'),
          StorageKey.random(),
        ),
        throwsA(isA<EncryptedStorageUnavailable>()),
      );
      schedules = CloudBackupScheduleStore.open(
        File('${root.path}/schedules.db'),
        scheduleKey,
      );
      expect((await schedules.due(start)).single.backupId, first.backupId);
      final afterOffline = start.add(const Duration(days: 3, hours: 2));
      expect(schedules.acknowledge(first, afterOffline), isTrue);
      expect(
        schedules.byProvider('provider-a')!.nextDueAt,
        start.add(const Duration(days: 4)),
      );
      expect(await schedules.due(afterOffline), isEmpty);
    },
  );

  test(
    'crash after enqueue reuses staged occurrence without rebuilding',
    () async {
      final work = CloudBackupWorkStore.open(
        databaseFile: File('${root.path}/work.db'),
        artifactDirectory: Directory('${root.path}/artifacts'),
        key: StorageKey.random(),
      );
      final jobs = PersistentJobStore.open(
        File('${root.path}/jobs.db'),
        StorageKey.random(),
      );
      final provider = _Provider();
      final runner = CloudBackupJobRunner(
        jobs: jobs,
        work: work,
        provider: provider,
      );
      schedules.configure(
        providerId: provider.providerId,
        enabled: true,
        interval: const Duration(days: 1),
        firstDueAt: start,
        now: start,
      );
      var builds = 0;
      Future<VerifiedBackupArtifact> build(
        String providerId,
        String backupId,
        DateTime dueAt,
      ) async {
        builds++;
        final created = await EnvelopeCodec().create(
          utf8.encode('{"scheduled":"$backupId"}'),
          password: password,
        );
        return VerifiedBackupArtifact.verify(
          backupId: backupId,
          envelope: created.envelope,
          password: password,
          recoveryKey: created.recoveryKey,
          createdAt: dueAt,
        );
      }

      final crashing = CloudBackupAutomaticScheduler(
        schedules: schedules,
        runners: {provider.providerId: runner},
        source: build,
        checkpoint: (point) {
          if (point == 'after-schedule') throw StateError('simulated crash');
        },
      );
      await expectLater(crashing.tick(start), throwsStateError);
      expect(builds, 1);
      expect(
        work.pendingBackupIds(providerId: provider.providerId),
        hasLength(1),
      );

      final resumed = CloudBackupAutomaticScheduler(
        schedules: schedules,
        runners: {provider.providerId: runner},
        source: build,
      );
      expect(await resumed.tick(start), 1);
      expect(builds, 1);
      expect(await schedules.due(start), isEmpty);
      work.close();
      jobs.close();
    },
  );

  test('an unresolved upload blocks automatic backup pile-up', () async {
    final work = CloudBackupWorkStore.open(
      databaseFile: File('${root.path}/blocked-work.db'),
      artifactDirectory: Directory('${root.path}/blocked-artifacts'),
      key: StorageKey.random(),
    );
    final jobs = PersistentJobStore.open(
      File('${root.path}/blocked-jobs.db'),
      StorageKey.random(),
    );
    final provider = _Provider();
    final runner = CloudBackupJobRunner(
      jobs: jobs,
      work: work,
      provider: provider,
    );
    final existing = await _artifact('manual-pending', start, password);
    await runner.schedule(existing, now: start);
    schedules.configure(
      providerId: provider.providerId,
      enabled: true,
      interval: const Duration(days: 1),
      firstDueAt: start,
      now: start,
    );
    var builds = 0;
    final automatic = CloudBackupAutomaticScheduler(
      schedules: schedules,
      runners: {provider.providerId: runner},
      source: (providerId, backupId, dueAt) async {
        builds++;
        return _artifact(backupId, dueAt, password);
      },
    );
    expect(await automatic.tick(start), 0);
    expect(builds, 0);
    expect(await schedules.due(start), hasLength(1));
    work.close();
    jobs.close();
  });
}

Future<VerifiedBackupArtifact> _artifact(
  String backupId,
  DateTime createdAt,
  String password,
) async {
  final created = await EnvelopeCodec().create(
    utf8.encode('{"backup":"$backupId"}'),
    password: password,
  );
  return VerifiedBackupArtifact.verify(
    backupId: backupId,
    envelope: created.envelope,
    password: password,
    recoveryKey: created.recoveryKey,
    createdAt: createdAt,
  );
}

final class _Provider implements CloudBackupProvider {
  @override
  String get providerId => 'provider-a';

  @override
  Future<List<int>> download(String objectId) => throw UnimplementedError();

  @override
  Future<RemoteBackupMetadata?> inspect(RemoteBackupReservation reservation) =>
      throw UnimplementedError();

  @override
  Future<RemoteBackupReservation> reserve(VerifiedBackupArtifact artifact) =>
      throw UnimplementedError();

  @override
  Future<RemoteBackupMetadata> upload(
    RemoteBackupReservation reservation,
    VerifiedBackupArtifact artifact,
  ) => throw UnimplementedError();
}
