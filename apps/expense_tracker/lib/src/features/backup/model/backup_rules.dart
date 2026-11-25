import 'package:core/foundation_values.dart' show BusinessDate, twoDigits;

import '../../../core/messages/backup_messages.dart';

/// The rules of the automatic backups, decided here once: how many stay,
/// how often one is made, and how the files and the Drive folder are
/// named. The app's own backups (`EncryptedBackupManager`, `PhoneBackup`,
/// `DriveSync`, `DriveBackup`) follow them, and the background job
/// (BackupWorker.kt), which delivers while the app is closed, is handed
/// them with each backup ([handover], in the outbox's `ready.json`): it
/// keeps no number, name or word of its own (review 32, 2.1).
abstract final class BackupRules {
  /// How many of a ledger's backups stay: in the app's own folder, the
  /// phone's folder and on Drive.
  static const keep = 5;

  /// The two rhythms the person chooses between for the phone's folder;
  /// the app's own backups are weekly and Drive's daily.
  static const daily = Duration(days: 1);
  static const weekly = Duration(days: 7);
  static const drive = daily;
  static const own = weekly;

  /// How often the phone's folder gets a backup.
  static Duration phoneEvery({required bool daily}) =>
      daily ? BackupRules.daily : weekly;

  /// The folder on Google Drive the backups go into.
  static const driveFolder = '記帳本備份';

  /// The start and end of the names of the backups in the phone's folder.
  static const _prefix = '記帳本-';
  static const suffix = '.etbk';

  /// A short mark of [ledger] in its backups' names, so the folder can
  /// hold another ledger's backups (such as one restored in its place)
  /// and only this ledger's are ever deleted.
  static String markOf(String ledger) {
    final plain = ledger.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    return plain.length > 6 ? plain.substring(0, 6) : plain;
  }

  /// How the names of the ledger marked [mark] start in the phone's folder.
  static String phonePrefix(String mark) => '$_prefix$mark-';

  /// The name of the backup of the ledger marked [mark] taken at [at] (on
  /// the phone's clock) in the phone's folder: sorts by time.
  static String phoneName(String mark, DateTime at) =>
      '${phonePrefix(mark)}${BusinessDate.of(at).compact}'
      '-${twoDigits(at.hour)}${twoDigits(at.minute)}$suffix';

  /// What the background job is handed with the backup of the ledger
  /// marked [mark] written at [at]: the rules above, the name that backup
  /// takes in the phone's folder, and the words it may have to say.
  static Map<String, Object?> handover(String mark, DateTime at) => {
    'keep': keep,
    'daily': daily.inMilliseconds,
    'weekly': weekly.inMilliseconds,
    'drive': drive.inMilliseconds,
    'phoneName': phoneName(mark, at),
    'phonePrefix': phonePrefix(mark),
    'suffix': suffix,
    'driveFolder': driveFolder,
    'folderDenied': BackupWords.folderDenied,
  };
}
