/// What the error log calls the faults it keeps without a caller naming
/// them itself: those nobody caught, and the steps that go on when they
/// fail (the app carries on with a default, a cache it fetches again or a
/// retry at the next start). Kept under one of these names, each can be
/// seen in 設定 › 關於 › 診斷. They are labels of the log, here so every
/// part of the app can name its step the same way.
abstract final class ErrorSteps {
  /// A fault while a screen was being built, laid out or drawn.
  static const screenError = '畫面錯誤';

  /// A fault nothing caught, outside the drawing of a screen.
  static const unforeseenError = '未預期的錯誤';

  /// A fault the Dart runtime reports for the whole isolate.
  static const isolateError = '背景執行錯誤';

  /// The error log's own file could not be read or written.
  static const logFile = '診斷紀錄';

  /// The settings file could not be read: the defaults are used.
  static const preferencesRead = '讀取設定';

  /// The settings file could not be written: kept in memory this run.
  static const preferencesWrite = '儲存設定';

  /// A form put aside (暫存) could not be read back.
  static const draft = '暫存的表單';

  /// The phone's copy of the market's day lists could not be read or
  /// written: the network is asked instead.
  static const marketCache = '行情快取';

  /// The phone's copy of past closing prices could not be read or
  /// written: fetched again.
  static const priceHistory = '歷史股價快取';

  /// A leftover file could not be looked at or deleted: tried again at
  /// the next start.
  static const cleanup = '清除暫存檔';

  /// The newest backup's header could not be read: a new one is written.
  static const backupHeader = '讀取備份檔';

  /// A backup chosen on Google Drive could not be downloaded to restore:
  /// the person is told and may choose again.
  static const backupDownload = '下載備份';

  /// Google was not told to revoke the app's access: it can be revoked
  /// from the Google account's settings.
  static const driveRevoke = '撤銷 Google 授權';

  /// Older backups on Drive could not be trashed: tried again after the
  /// next upload.
  static const driveTrim = '清理雲端舊備份';

  /// The phone could not say whether notifications are allowed.
  static const notificationStatus = '通知狀態';

  /// The plan of notifications could not be handed to the phone: handed
  /// again at the next change or start.
  static const notifications = '通知';

  /// The inbox of confirmations from notifications could not be read, or
  /// what it booked was not kept: its items stay for the next time.
  static const inbox = '收件匣';

  /// The chosen calendar could not be brought up to date: tried again at
  /// the next change or start.
  static const calendarSync = '日曆同步';

  /// The app's events could not be taken off a calendar no longer
  /// synced: they stay there for the person to delete.
  static const calendarClear = '清除日曆的提醒';

  /// The phone could not say whether it hides the app in the recents
  /// list, or could not be told to: the app keeps covering itself.
  static const screenPrivacy = '螢幕隱私';
}
