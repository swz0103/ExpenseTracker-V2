import 'package:cloud_backup_probe/cloud_backup.dart';
import 'package:cloud_backup_probe/cloud_backup_history.dart';
import 'package:cloud_backup_probe/cloud_backup_manual_flow.dart';
import 'package:cloud_backup_probe/cloud_backup_schedule.dart';

import 'cloud_backup_screen.dart';

typedef CloudBackupSourceFactory = Future<VerifiedBackupArtifact> Function();
typedef CloudBackupRestoreHandoff = Future<void> Function(
  String envelope,
  CloudBackupCredentialKind kind,
  String credential,
);

/// Bridges the provider-neutral use cases to the standalone Flutter screen.
/// The final app integration supplies an engine-backed source factory and the
/// existing clean-restore handoff without changing screen behavior.
final class FlowCloudBackupScreenGateway implements CloudBackupScreenGateway {
  const FlowCloudBackupScreenGateway({
    required this.flow,
    required this.providerChoices,
    required this.createSource,
    required this.restoreHandoff,
    required this.schedules,
  });

  final CloudBackupManualFlow flow;
  final List<CloudBackupProviderChoice> providerChoices;
  final CloudBackupSourceFactory createSource;
  final CloudBackupRestoreHandoff restoreHandoff;
  final CloudBackupScheduleStore schedules;

  @override
  List<CloudBackupProviderChoice> get providers => providerChoices;

  @override
  Future<void> createBackup(String providerId) async {
    final source = await createSource();
    await flow.scheduleVerifiedBackup(
      providerId: providerId,
      artifact: source,
      now: DateTime.now().toUtc(),
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
}
