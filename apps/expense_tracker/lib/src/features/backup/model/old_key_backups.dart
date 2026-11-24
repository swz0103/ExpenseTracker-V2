import 'dart:io';

import '../../../core/diagnostics/error_log.dart';
import '../../../core/diagnostics/error_steps.dart';
import 'drive_backup.dart';

/// The backups sealed with keys a reset has since replaced (D15): their
/// headers carry the old keyring, which the old recovery code and
/// password still open. Found after a reset of the keys, listed with
/// their dates, and taken away only once the person confirms.
final class OldKeyBackups {
  const OldKeyBackups({
    required this.epoch,
    required this.localBackups,
    this.driveFiles,
    this.trashOnDrive,
  });

  /// The backup key epoch backups are sealed with now: one of an earlier
  /// epoch was sealed before the reset.
  final int epoch;

  /// The backups the app keeps on the phone (its weekly backups, the
  /// copies kept before a restore or an upgrade), each with the key epoch
  /// and the time its header names; one that cannot be read left out.
  final Future<List<(File, int epoch, DateTime at)>> Function() localBackups;

  /// This ledger's backups on Google Drive; none when Drive is not linked.
  final Future<List<DriveFile>> Function()? driveFiles;

  /// Moves a backup on Drive to its trash.
  final Future<void> Function(String id)? trashOnDrive;

  /// The backups of earlier keys, on Drive and on the phone. On Drive,
  /// every one not marked with the epoch of now ([DriveFile.epoch]): one
  /// sent before backups were marked was sent by an earlier version of
  /// the app, so before this reset; asked right after a reset, none is
  /// marked with a later epoch.
  /// Drive not answering leaves its list out ([OldKeyBackupsFound.driveUnreached]).
  Future<OldKeyBackupsFound> find() async {
    var drive = const <DriveFile>[];
    var unreached = false;
    if (driveFiles case final list?) {
      try {
        drive = [
          for (final file in await list())
            if (file.epoch != '$epoch') file,
        ];
      } on Object catch (error) {
        ErrorLog.instance.record(ErrorSteps.oldKeyBackups, error);
        unreached = true;
      }
    }
    final local = [
      for (final (file, sealed, at) in await localBackups())
        if (sealed < epoch) (file, at),
    ];
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
        ErrorLog.instance.record(ErrorSteps.oldKeyBackups, error);
      }
    }
    for (final (file, _) in found.local) {
      try {
        if (file.existsSync()) await file.delete();
        gone++;
      } on Object catch (error) {
        ErrorLog.instance.record(ErrorSteps.oldKeyBackups, error);
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
