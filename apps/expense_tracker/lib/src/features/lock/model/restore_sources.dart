import 'dart:io';

import '../../backup/model/drive_backup.dart';

/// Where the lock screen can find a backup to restore, from the phone:
/// the system's file picker and Google Drive. Each is absent where the
/// phone does not offer it; without a picker the path is typed.
final class RestoreSources {
  const RestoreSources({this.pickFile, this.drive, this.cacheDirectory});

  /// Lets the person choose a file and returns the path of a copy.
  final Future<String?> Function()? pickFile;

  /// The backups on Google Drive.
  final DriveBackup Function()? drive;

  /// Where a backup taken from Drive is kept until restored.
  final Future<Directory> Function()? cacheDirectory;
}
