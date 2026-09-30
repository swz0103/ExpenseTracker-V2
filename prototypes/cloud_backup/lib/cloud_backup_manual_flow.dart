import 'cloud_backup.dart';
import 'cloud_backup_history.dart';

enum CloudBackupCredentialKind { password, recoveryKey }

enum ManualCloudBackupState { queued }

final class ManualCloudBackupReceipt {
  const ManualCloudBackupReceipt({
    required this.providerId,
    required this.backupId,
    required this.createdAt,
    required this.state,
  });

  final String providerId;
  final String backupId;
  final DateTime createdAt;
  final ManualCloudBackupState state;
}

typedef CloudBackupSchedule = Future<void> Function(
  VerifiedBackupArtifact artifact,
  DateTime now,
);

final class CloudBackupManualTarget {
  const CloudBackupManualTarget({
    required this.providerId,
    required this.schedule,
  });

  final String providerId;
  final CloudBackupSchedule schedule;
}

/// App-facing use cases without any provider-specific branching. UI owns the
/// explicit confirmation and supplies a stable backup ID for retries.
final class CloudBackupManualFlow {
  CloudBackupManualFlow({
    required this.providers,
    required Iterable<CloudBackupManualTarget> uploadTargets,
  }) : _targets = _index(uploadTargets, providers);

  final CloudBackupProviderRegistry providers;
  final Map<String, CloudBackupManualTarget> _targets;

  List<String> get providerIds => providers.providerIds;

  Future<ManualCloudBackupReceipt> scheduleBackup({
    required String providerId,
    required String backupId,
    required String envelope,
    required String password,
    required String recoveryKey,
    required DateTime createdAt,
    required DateTime now,
  }) async {
    final target = _targets[providerId];
    if (target == null) {
      throw StateError('Provider is not configured for upload');
    }
    final artifact = await VerifiedBackupArtifact.verify(
      backupId: backupId,
      envelope: envelope,
      password: password,
      recoveryKey: recoveryKey,
      createdAt: createdAt,
    );
    await target.schedule(artifact, now.toUtc());
    return ManualCloudBackupReceipt(
      providerId: providerId,
      backupId: backupId,
      createdAt: createdAt.toUtc(),
      state: ManualCloudBackupState.queued,
    );
  }

  Future<List<RemoteBackupMetadata>> history(String providerId) =>
      CloudBackupRetentionService(providers.catalog(providerId)).history();

  Future<String> downloadForRestore({
    required String providerId,
    required RemoteBackupMetadata backup,
    required CloudBackupCredentialKind credentialKind,
    required String credential,
  }) {
    if (credential.isEmpty) throw ArgumentError.value(credential, 'credential');
    final coordinator = CloudBackupCoordinator(providers.provider(providerId));
    return switch (credentialKind) {
      CloudBackupCredentialKind.password => coordinator.downloadAndVerify(
        backup,
        password: credential,
      ),
      CloudBackupCredentialKind.recoveryKey => coordinator.downloadAndVerify(
        backup,
        recoveryKey: credential,
      ),
    };
  }

  Future<CloudBackupRetentionPlan> previewRetention({
    required String providerId,
    required CloudBackupRetentionPolicy policy,
    required DateTime now,
  }) =>
      CloudBackupRetentionService(providers.catalog(providerId))
          .preview(policy, now: now);

  Future<void> applyRetention(CloudBackupRetentionPlan plan) =>
      CloudBackupRetentionService(providers.catalog(plan.providerId))
          .apply(plan);

  static Map<String, CloudBackupManualTarget> _index(
    Iterable<CloudBackupManualTarget> targets,
    CloudBackupProviderRegistry providers,
  ) {
    final result = <String, CloudBackupManualTarget>{};
    for (final target in targets) {
      providers.provider(target.providerId);
      if (result.containsKey(target.providerId)) {
        throw StateError('Duplicate cloud backup upload target');
      }
      result[target.providerId] = target;
    }
    return Map.unmodifiable(result);
  }
}
