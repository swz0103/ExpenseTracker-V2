import 'package:cloud_backup_probe/cloud_backup.dart';
import 'package:cloud_backup_probe/cloud_backup_manual_flow.dart';
import 'package:foundation_values/foundation_values.dart';

import 'preview_engine.dart';

/// Confines cloud backup creation and restore to the unlocked engine boundary.
/// Neither operation exposes or persists the profile password or recovery key.
final class EngineCloudBackupBridge {
  EngineCloudBackupBridge({
    required this.engine,
    this.now = DateTime.now,
    String Function()? backupId,
  }) : _backupId = backupId ?? _newBackupId;

  final PreviewEngine engine;
  final DateTime Function() now;
  final String Function() _backupId;

  Future<VerifiedBackupArtifact> createSource() {
    final createdAt = now().toUtc();
    return engine.exportVerifiedCloudBackup(
      backupId: _backupId(),
      createdAt: createdAt,
    );
  }

  Future<void> restore(
    String envelope,
    CloudBackupCredentialKind kind,
    String credential,
  ) => engine.importBackup(
    envelope,
    credential,
    recovery: kind == CloudBackupCredentialKind.recoveryKey,
  );

  static String _newBackupId() => 'manual-${PublicId.generate().value}';
}
