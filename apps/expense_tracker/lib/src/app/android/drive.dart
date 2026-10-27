import '../../features/backup/model/drive_backup.dart';
import 'channel.dart';

/// An access token for the app's own files on Google Drive; null when the
/// person did not allow it, or, without [interactive], has not yet.
Future<String?> androidDriveToken({required bool interactive}) =>
    platformChannel.invokeMethod<String>('driveToken', {
      'interactive': interactive,
    });

/// Tells Google to forget [token], which it refused or the person no
/// longer wants used.
Future<void> androidClearDriveToken(String token) =>
    platformChannel.invokeMethod<void>('clearDriveToken', {'token': token});

/// Backups on Google Drive through the phone's Google account.
DriveBackup androidDrive() => DriveBackup(
  const IoDriveHttp(),
  token: androidDriveToken,
  forget: androidClearDriveToken,
);
