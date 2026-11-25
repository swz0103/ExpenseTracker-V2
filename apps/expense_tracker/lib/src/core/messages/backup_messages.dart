/// The words of the backup settings, in one place.
abstract final class BackupWords {
  /// Google Drive: the person did not allow access.
  static const driveNotAllowed = '沒有取得 Google 雲端硬碟的權限';

  /// Google Drive could not be reached.
  static const driveOffline = '連不上 Google，請稍後再試';

  /// Google's sign-in gave no answer.
  static const driveNoAnswer = 'Google 沒有回應，請再試一次';

  /// Drive refused or failed a request: its answer is in the
  /// diagnostics, never said (D84).
  static const driveRefused = 'Google 雲端硬碟沒有接受這次的要求';

  /// The Google account a Drive card's backups go to.
  static const account = '帳號';

  /// A diagnostics heading: asking Google which account is linked.
  static const accountLookup = 'Google 帳號';

  /// Backups with the receipt photos go on any network
  /// (Preferences.photosOnWifi off).
  static const photosAnyNetwork = '任何網路都一起備份';

  /// The switch that keeps backups with the photos to Wi-Fi, and what
  /// turning it off means.
  static const photosOnWifi = '只用 Wi-Fi 上傳照片';
  static const photosOnWifiOff = '關閉時行動網路也會上傳，可能用掉較多流量';

  /// The folder on Google Drive the backups go into, and how the names of
  /// the backups in the phone's folder start: the person sees both, and
  /// the backups already there carry them (`BackupRules`).
  static const driveFolder = '記帳本備份';
  static const phoneNameStart = '記帳本-';
}
