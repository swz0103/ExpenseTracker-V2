import 'dart:io';

import 'package:vault/ledger_backup.dart';

import '../../../core/diagnostics/error_log.dart';
import 'drive_backup.dart';

/// The backups sealed with keys a reset has since replaced (D15): their
/// headers carry the old keyring, which the old recovery code and
/// password still open. Found after a reset of the keys, listed with
/// their dates, and taken away only once the person confirms.
final class OldKeyBackups {
  const OldKeyBackups({
    required this.epoch,
    required this.localFiles,
    this.driveFiles,
    this.trashOnDrive,
  });

  /// The backup key epoch backups are sealed with now: one of an earlier
  /// epoch was sealed before the reset.
  final int epoch;

  /// The backup files kept on the phone by the app (its weekly backups,
  /// the copies kept before a restore or an upgrade).
  final List<File> Function() localFiles;

  /// This ledger's backups on Google Drive; none when Drive is not linked.
  final Future<List<DriveFile>> Function()? driveFiles;

  /// Moves a backup on Drive to its trash.
  final Future<void> Function(String id)? trashOnDrive;

  /// The backups of earlier keys, on Drive and on the phone. A backup on
  /// Drive sent before backups were marked with their epoch was sent by
  /// an earlier version of the app, so before this reset: it is one too.
  /// Drive not answering leaves its list out ([OldKeyBackupsFound.driveUnreached]).
  Future<OldKeyBackupsFound> find() async {
    var drive = const <DriveFile>[];
    var unreached = false;
    if (driveFiles case final list?) {
      try {
        drive = [
          for (final file in await list())
            if ((file.epoch ?? 0) < epoch) file,
        ];
      } on Object catch (error) {
        ErrorLog.instance.record('找舊金鑰的備份', error);
        unreached = true;
      }
    }
    final local = <(File, DateTime)>[];
    for (final file in localFiles()) {
      try {
        final header = await LedgerBackup.readHeader(file);
        if (header.backupEpoch < epoch) local.add((file, header.createdAt));
      } on Object catch (error) {
        // Not a backup this can read: left as it is.
        ErrorLog.instance.record('找舊金鑰的備份', error);
      }
    }
    local.sort((a, b) => b.$2.compareTo(a.$2));
    return OldKeyBackupsFound(drive, local, driveUnreached: unreached);
  }

  /// Takes [found] away: to the Drive trash, and off the phone. How many
  /// went; one that could not is noted and left.
  Future<int> remove(OldKeyBackupsFound found) async {
    var gone = 0;
    for (final file in found.drive) {
      try {
        await trashOnDrive?.call(file.id);
        gone++;
      } on Object catch (error) {
        ErrorLog.instance.record('刪除舊金鑰的備份', error);
      }
    }
    for (final (file, _) in found.local) {
      try {
        if (file.existsSync()) await file.delete();
        gone++;
      } on Object catch (error) {
        ErrorLog.instance.record('刪除舊金鑰的備份', error);
      }
    }
    return gone;
  }
}

/// What [OldKeyBackups.find] found: newest first on each side.
final class OldKeyBackupsFound {
  const OldKeyBackupsFound(
    this.drive,
    this.local, {
    this.driveUnreached = false,
  });

  final List<DriveFile> drive;
  final List<(File, DateTime)> local;

  /// Drive is linked but did not answer: its backups are not listed.
  final bool driveUnreached;

  bool get isEmpty => drive.isEmpty && local.isEmpty;
}
