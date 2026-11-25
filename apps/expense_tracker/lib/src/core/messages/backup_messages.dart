/// The words of the backup settings, in one place.
abstract final class BackupWords {
  /// Asked before a restore from another backup, and its yes.
  static const restoreAsk = '從備份還原？';
  static const restoreAskBody = '會先把目前的帳本連同照片備份一份，再換成你選的備份';
  static const restoreChoose = '選擇備份';

  /// Asked before backups to Google Drive stop, and what stays.
  static const driveStopAsk = '不再備份到 Google 雲端硬碟？';
  static const driveStopBody = '已經在雲端的備份會留著';

  /// Asked before backups to the phone's folder stop, and what stays.
  static const folderStopAsk = '停止自動備份到手機？';
  static const folderStopBody = '資料夾裡的備份會留著';

  /// What stops a way of backing up: red, as it cannot be undone.
  static const stop = '停止';

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

  /// The phone's folder chosen for backups no longer lets the app write
  /// (`FolderDenied`), and the button that opens the chooser again.
  static const folderDenied = '沒有這個資料夾的存取權，請重新選擇';
  static const chooseFolderAgain = '重新選擇';
}
