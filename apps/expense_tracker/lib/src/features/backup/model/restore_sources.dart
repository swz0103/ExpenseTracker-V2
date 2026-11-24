import 'dart:io';

import 'drive_backup.dart';

/// Where the lock screen can find a backup to restore, from the phone:
/// the system's file picker and Google Drive. Each is absent where the
/// phone does not offer it; without a picker the path is typed.
final class RestoreSources {
  const RestoreSources({
    this.pickFile,
    this.drive,
    this.cacheDirectory,
    this.deliveredRevision,
  });

  /// Lets the person choose a file and returns the path of a copy.
  final Future<String?> Function()? pickFile;

  /// The backups on Google Drive.
  final DriveBackup Function()? drive;

  /// Where a backup taken from Drive is kept until restored.
  final Future<Directory> Function()? cacheDirectory;

  /// The most a backup of this phone's ledger is known to have been
  /// delivered or to wait at (`Outbox.deliveredRevision`), read as a
  /// backup is restored: the book restored goes on from above it, so it
  /// passes every delivery (review 28). Absent, nothing is known.
  final int Function()? deliveredRevision;
}
