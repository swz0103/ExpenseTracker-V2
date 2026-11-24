import '../../../core/messages/backup_messages.dart';
import '../../../core/messages/problem_messages.dart';
import '../model/drive_backup.dart';

/// What the person is told of [error], a Drive request that did not go
/// through: what to do, or that Drive refused, its answer kept for the
/// diagnostics rather than said (D84).
String driveNote(DriveException error) => switch (error.problem) {
  DriveProblem.notAllowed => BackupWords.driveNotAllowed,
  DriveProblem.offline => BackupWords.driveOffline,
  DriveProblem.noAnswer => BackupWords.driveNoAnswer,
  DriveProblem.refused => failureNote(BackupWords.driveRefused),
};
