import 'dart:io';

import '../../../core/diagnostics/error_log.dart';
import '../../../core/diagnostics/error_steps.dart';
import 'drive_backup.dart';
import 'phone_backup.dart' show FolderFile;

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
    this.folderBackups,
    this.deleteInFolder,
    this.keptDatabases,
    this.deleteDatabase,
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

  /// This ledger's backups in the folder chosen on the phone written
  /// before the reset (`PhoneBackup.writtenBefore`): the folder is the
  /// person's own, often copied by another app, so they are listed, never
  /// taken without asking. None when no folder is chosen.
  final Future<List<FolderFile>> Function()? folderBackups;

  /// Deletes a backup from the folder on the phone.
  final Future<void> Function(String id)? deleteInFolder;

  /// The databases kept beside the ledger, set aside as damaged or in the
  /// old format, with when each was last written: all made before the
  /// reset, so encrypted with the old keys.
  final List<(File, DateTime)> Function()? keptDatabases;

  /// Deletes one of [keptDatabases], with its log.
  final Future<void> Function(File file)? deleteDatabase;

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
    var folder = const <FolderFile>[];
    var folderUnreached = false;
    if (folderBackups case final list?) {
      try {
        folder = await list();
      } on Object catch (error) {
        ErrorLog.instance.record(ErrorSteps.oldKeyBackups, error);
        folderUnreached = true;
      }
    }
    final local = [
      for (final (file, sealed, at) in await localBackups())
        if (sealed < epoch) (file, at),
    ];
    local.sort((a, b) => b.$2.compareTo(a.$2));
    final databases = [...?keptDatabases?.call()]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return OldKeyBackupsFound(
      drive,
      local,
      folder: folder,
      databases: databases,
      driveUnreached: unreached,
      folderUnreached: folderUnreached,
    );
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
    for (final file in found.folder) {
      try {
        await deleteInFolder?.call(file.id);
        gone++;
      } on Object catch (error) {
        ErrorLog.instance.record(ErrorSteps.oldKeyBackups, error);
      }
    }
    for (final (file, _) in found.databases) {
      try {
        await deleteDatabase?.call(file);
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
    this.folder = const [],
    this.databases = const [],
    this.driveUnreached = false,
    this.folderUnreached = false,
  });

  final List<DriveFile> drive;

  /// The app's own backups on the phone.
  final List<(File, DateTime)> local;

  /// Backups in the folder chosen on the phone.
  final List<FolderFile> folder;

  /// Databases kept beside the ledger, damaged or in the old format.
  final List<(File, DateTime)> databases;

  /// Drive is linked but did not answer: its backups are not listed.
  final bool driveUnreached;

  /// The folder on the phone could not be read: its backups are not
  /// listed.
  final bool folderUnreached;

  bool get isEmpty =>
      drive.isEmpty && local.isEmpty && folder.isEmpty && databases.isEmpty;
}
