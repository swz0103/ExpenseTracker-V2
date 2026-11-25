import 'dart:io';

import '../../../core/messages/backup_messages.dart';
import '../../../core/messages/problem_messages.dart';
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

/// What the person is told of [error], a Drive request that did not go
/// through, here or as a backup is restored: what to do, or that Drive
/// refused, its answer kept for the diagnostics rather than said (D84).
String driveNote(DriveException error) => switch (error.problem) {
  DriveProblem.notAllowed => BackupWords.driveNotAllowed,
  DriveProblem.offline => BackupWords.driveOffline,
  DriveProblem.noAnswer => BackupWords.driveNoAnswer,
  DriveProblem.refused => failureNote(BackupWords.driveRefused),
};
