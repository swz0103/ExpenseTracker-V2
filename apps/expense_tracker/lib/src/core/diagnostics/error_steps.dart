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

  /// A receipt photo could not be taken, taken back or kept.
  static const receiptPhoto = '收據照片';

  /// The phone's copy of the market's day lists could not be read or
  /// written: the network is asked instead.
  static const marketCache = '行情快取';

  /// The phone's copy of past closing prices could not be read or
  /// written: fetched again.
  static const priceHistory = '歷史股價快取';

  /// The backup waiting for the background job could not be taken away
  /// after a reset of the keys: replaced by the next one written.
  static const outboxEmpty = '清空背景備份';

  /// A leftover file could not be looked at or deleted: tried again at
  /// the next start.
  static const cleanup = '清除暫存檔';

  /// The newest backup's header could not be read: a new one is written.
  static const backupHeader = '讀取備份檔';

  /// A backup chosen on Google Drive could not be downloaded to restore:
  /// the person is told and may choose again.
  static const backupDownload = '下載備份';

  /// Linking Google Drive, or sending a backup there with the photos,
  /// was refused or failed: the person is told and may try again.
  static const driveBackup = '雲端硬碟備份';

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

  /// The journal of postings could not be brought up to date with a
  /// change of the records: it is posted afresh when the book next opens.
  /// Nothing the person sees reads it yet.
  static const journalUpdate = '分錄更新';

  /// The journal's sums differ from the figures the app shows: which
  /// figures, never an amount. Nothing the person sees reads it yet.
  static const journalParity = '分錄比對';

  /// The app's own folder could not be found as it started: nothing can
  /// open, the failure page says so.
  static const startFolder = '啟動：帳本資料夾';

  /// The phone could not say whether it unlocks with a fingerprint or
  /// face as the app started: the app starts without it.
  static const startDevice = '啟動：生物辨識解鎖';

  /// The first screen could not be put together.
  static const startScreen = '啟動：第一個畫面';

  /// The phone's SQLite is built without threads, so a backup's read on
  /// a worker is not kept apart from the app's own (D41).
  static const storeThreading = '啟動：資料庫執行緒模式';

  /// The copy of a book kept before its upgrade could not be written, or
  /// the person went on without it (D19).
  static const upgradeBackup = '升級前備份';

  /// The fingerprint of the rows set aside last told could not be read
  /// or kept: the notice is given again (D18).
  static const quarantineNotice = '隔離提示';

  /// A backup of keys a reset replaced could not be listed or taken away
  /// (D15).
  static const oldKeyBackups = '舊金鑰的備份';

  /// Rows of the book set aside as it opened, how many (no contents).
  /// The ledger's file found damaged, set aside for a backup (D94).
  static const bookDamaged = '帳本檔案損毀';

  /// The ledger's file made again from its records, its journal's tables
  /// found damaged (D102).
  static const journalRebuilt = '分錄重建';

  /// The note that the journal's tables were found damaged (D102), so
  /// the next opening makes the book again, could not be written (the
  /// book is still made again now), or could not be let go of once the
  /// book was made again (the next opening makes it again; review 28).
  static const journalDamagedNote = '分錄損毀標記';

  /// The ledger's file, made again from its records (D102), could not be
  /// opened just then: it is kept, and the lock screen opens it again.
  static const rebuiltNotOpened = '重建後打開帳本';

  /// Making the ledger's file again from its records (D102) failed before
  /// the copy was put in place (a disk full, say): the file is kept as
  /// it was, and made again at the next opening (D113).
  static const salvageNotMade = '重建帳本未完成';

  /// The second worker a large book's opening decodes half its entries
  /// on could not be started, or failed: the book opened all the same,
  /// that half decoded on the first (review 24).
  static const openingHelper = '打開帳本：第二個工作執行緒';

  /// The note that records were kept in the ledger's file (D102) could
  /// not be written as a write was kept: the write stands, and the note
  /// is tried again at the next write and the next opening.
  static const recordsKeptNote = '帳本寫入標記';

  /// A close or rate fetched that was doubted and set aside (D95).
  static const doubtfulQuote = '可疑的行情';

  static const bookOpen = '打開帳本';
}
