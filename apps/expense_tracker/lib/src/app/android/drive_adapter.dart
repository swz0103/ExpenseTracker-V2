import 'package:vault/ledger_backup.dart' show LedgerBackup;

import '../../core/platform/errands.dart';
import '../../features/backup/model/drive_backup.dart';
import 'platform_channel.dart';

/// An access token for the app's own files on Google Drive; null when the
/// person did not allow it, or, without [interactive], has not yet.
/// Asking with [interactive] may show Google's sign-in: a trip out of the
/// app.
Future<String?> androidDriveToken({required bool interactive}) {
  Future<String?> ask() => platformChannel.invokeMethod<String>('driveToken', {
    'interactive': interactive,
  });
  return interactive ? Errands.run(ask) : ask();
}

/// Tells Google to forget [token], which it refused or the person no
/// longer wants used.
Future<void> androidClearDriveToken(String token) =>
    platformChannel.invokeMethod<void>('clearDriveToken', {'token': token});

/// Backups on Google Drive through the phone's Google account.
DriveBackup androidDrive() => DriveBackup(
  const IoDriveHttp(saveLimit: LedgerBackup.maxBackupBytes),
  token: androidDriveToken,
  forget: androidClearDriveToken,
);
