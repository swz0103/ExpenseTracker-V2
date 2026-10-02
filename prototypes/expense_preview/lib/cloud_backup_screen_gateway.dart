import 'package:cloud_backup_probe/cloud_backup.dart';
import 'package:cloud_backup_probe/cloud_backup_history.dart';
import 'package:cloud_backup_probe/cloud_backup_manual_flow.dart';
import 'package:cloud_backup_probe/cloud_backup_schedule.dart';
import 'package:cloud_backup_probe/cloud_backup_work.dart';

import 'cloud_backup_screen.dart';

typedef CloudBackupSourceFactory = Future<VerifiedBackupArtifact> Function();
typedef CloudBackupRestoreHandoff = Future<void> Function(
  String envelope,
  CloudBackupCredentialKind kind,
  String credential,
);
typedef CloudBackupReconnect = Future<void> Function(String providerId);

/// Bridges the provider-neutral use cases to the standalone Flutter screen.
/// The final app integration supplies an engine-backed source factory and the
/// existing clean-restore handoff without changing screen behavior.
final class FlowCloudBackupScreenGateway
    implements
        CloudBackupScreenGateway,
        CloudBackupRuntimeGateway,
        CloudBackupPendingRuntimeGateway {
  FlowCloudBackupScreenGateway({
    required this.flow,
    required this.providerChoices,
    required this.createSource,
    required this.restoreHandoff,
    required this.schedules,
    this.runners = const {},
    this.automaticScheduler,
    this.maximumJobsPerPump = 4,
    this.reconnectProvider,
  }) {
    if (maximumJobsPerPump < 1 || maximumJobsPerPump > 20) {
      throw ArgumentError.value(maximumJobsPerPump, 'maximumJobsPerPump');
    }
  }

  final CloudBackupManualFlow flow;
  final List<CloudBackupProviderChoice> providerChoices;
  final CloudBackupSourceFactory createSource;
  final CloudBackupRestoreHandoff restoreHandoff;
  final CloudBackupScheduleStore schedules;
  final Map<String, CloudBackupJobRunner> runners;
  final CloudBackupAutomaticScheduler? automaticScheduler;
  final int maximumJobsPerPump;
  final CloudBackupReconnect? reconnectProvider;

  @override
  List<CloudBackupProviderChoice> get providers => providerChoices;

  @override
  bool canReconnect(String providerId) =>
      reconnectProvider != null &&
      providerChoices.any((provider) => provider.id == providerId);

  @override
  Future<void> reconnect(String providerId) async {
    if (!canReconnect(providerId)) {
      throw const CloudBackupProviderException(
        CloudBackupProviderFailure.authenticationRequired,
      );
    }
    await reconnectProvider!(providerId);
    final runner = runners[providerId];
    if (runner != null) {
      final now = DateTime.now().toUtc();
      for (final backupId in runner.work.pendingBackupIds(
        providerId: providerId,
      )) {
        await runner.retryAfterUserAction(backupId, now);
      }
      runner.reconcile(now);
      await _runProvider(providerId, now, throwFailures: true);
    }
  }

  @override
  Future<void> createBackup(String providerId) async {
    final source = await createSource();
    final now = DateTime.now().toUtc();
    await flow.scheduleVerifiedBackup(
      providerId: providerId,
      artifact: source,
      now: now,
    );
    await _runProvider(providerId, now, throwFailures: true);
  }

  @override
  Future<CloudBackupRuntimeReport> maintainRuntime(
    String providerId,
    DateTime now,
  ) async {
    await automaticScheduler?.tick(now.toUtc());
    return maintainPendingRuntime(providerId, now);
  }

  @override
  Future<CloudBackupRuntimeReport> maintainPendingRuntime(
    String providerId,
    DateTime now,
  ) async {
    final runner = runners[providerId];
    runner?.reconcile(now.toUtc());
    await _runProvider(providerId, now.toUtc(), throwFailures: false);
    if (runner == null) {
      return const CloudBackupRuntimeReport(pendingJobs: 0);
    }
    final pending = runner.work.pendingBackupIds(providerId: providerId);
    CloudBackupWorkFailure? lastFailure;
    for (final backupId in pending.reversed) {
      final failure = runner.work.byId(backupId)?.lastFailure;
      if (failure != null) {
        lastFailure = failure;
        break;
      }
    }
    final latest = runner.work.latest(providerId: providerId);
    final latestUploaded = runner.work.latest(
      providerId: providerId,
      state: CloudBackupWorkState.uploaded,
    );
    return CloudBackupRuntimeReport(
      pendingJobs: pending.length,
      lastFailure: lastFailure,
      lastScheduledFor: latest?.scheduledFor,
      lastCapturedAt: latest?.createdAt,
      lastSuccessfulUploadAt: latestUploaded?.updatedAt,
    );
  }

  @override
  Future<List<RemoteBackupMetadata>> history(String providerId) =>
      flow.history(providerId);

  @override
  Future<void> restore({
    required String providerId,
    required RemoteBackupMetadata backup,
    required CloudBackupCredentialKind credentialKind,
    required String credential,
  }) async {
    final envelope = await flow.downloadForRestore(
      providerId: providerId,
      backup: backup,
      credentialKind: credentialKind,
      credential: credential,
    );
    await restoreHandoff(envelope, credentialKind, credential);
  }

  @override
  Future<CloudBackupRetentionPlan> previewRetention({
    required String providerId,
    required int keepLatest,
    required DateTime now,
  }) => flow.previewRetention(
    providerId: providerId,
    policy: CloudBackupRetentionPolicy(keepLatest: keepLatest),
    now: now,
  );

  @override
  Future<void> applyRetention(CloudBackupRetentionPlan plan) =>
      flow.applyRetention(plan);

  @override
  Future<CloudBackupScheduleRecord?> schedule(String providerId) async =>
      schedules.byProvider(providerId);

  @override
  Future<void> configureSchedule({
    required String providerId,
    required bool enabled,
    required Duration interval,
    required DateTime firstDueAt,
    required DateTime now,
  }) async => schedules.configure(
    providerId: providerId,
    enabled: enabled,
    interval: interval,
    firstDueAt: firstDueAt,
    now: now,
  );

  Future<void> _runProvider(
    String providerId,
    DateTime now, {
    required bool throwFailures,
  }) async {
    final runner = runners[providerId];
    if (runner == null) return;
    for (var i = 0; i < maximumJobsPerPump; i++) {
      try {
        if (!await runner.runNext(now)) return;
      } catch (_) {
        if (throwFailures) rethrow;
        return;
      }
    }
  }
}
