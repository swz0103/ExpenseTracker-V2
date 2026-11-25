import 'package:flutter/foundation.dart';

/// The keys tests find the app's controls by, so a test keeps working
/// when the words on a button change. Tests look for words only to check
/// the words themselves (docs/conventions.md).
abstract final class Keys {
  /// A tab of the bar at the foot, by its name: 總覽, 紀錄, 帳戶, 更多.
  static Key tab(String name) => ValueKey('tab:$name');

  /// A tool's tile in 更多 or a card on 設定, by its name.
  static Key tool(String name) => ValueKey('tool:$name');

  /// A button a row slides open, such as 編輯 or 刪除.
  static Key swipe(String name) => ValueKey('swipe:$name');

  /// The button of a note at the foot of the screen, such as 復原.
  static Key snack(String name) => ValueKey('snack:$name');

  /// A key of the amount calculator: a digit, an operation or 完成.
  static Key calc(String name) => ValueKey('calc:$name');

  /// Why the calculator's sum cannot be kept, under its figure.
  static const calcProblem = ValueKey('calc-problem');

  /// The composer's main button: 記下支出, 記下代墊 and the like.
  static const save = ValueKey('compose:save');

  /// The composer's 刪除 (an entry looked at) or 暫存 (a new one).
  static const discard = ValueKey('compose:discard');

  /// The yes of a question asked before something is done, such as 刪除.
  static const confirm = ValueKey('dialog:confirm');

  /// [confirm]'s other choice, 取消 or what it was named.
  static const confirmCancel = ValueKey('dialog:cancel');

  /// The line typed into askText's panel.
  static const askedText = ValueKey('dialog:text');

  /// An edit form's 取消 (EditGuard).
  static const cancelEdit = ValueKey('form:cancel');

  /// A way out of a book that could not be opened: retry, restore or
  /// export.
  static Key loadFailed(String what) => ValueKey('load-failed:$what');

  /// 匯出診斷 under a failure line of the lock or welcome views (review
  /// 31).
  static const exportDiagnostics = ValueKey('diagnostics:export');

  /// A way out of a book held back from its upgrade because the copy
  /// before it could not be kept: retry, export, or go on without it.
  static Key upgradeHeld(String what) => ValueKey('upgrade-held:$what');

  /// A way on from the notice of rows set aside: export, restore or
  /// continue.
  static Key quarantine(String what) => ValueKey('quarantine:$what');

  /// 刪除 on the bar over entries picked by a long press.
  static const deletePicked = ValueKey('ledger:delete-picked');

  /// The receipt square on the composer, while it has no photo.
  static const receipt = ValueKey('compose:receipt');

  /// Where a receipt's photo comes from: the camera, or the album.
  static Key receiptSource({required bool camera}) =>
      ValueKey('receipt:${camera ? 'camera' : 'album'}');

  /// The composer's fold of merchant, tags, note and receipt.
  static const extras = ValueKey('compose:extras');

  /// 完成 over the account wallet while its cards turn.
  static const walletDone = ValueKey('wallet:done');

  /// 完成 at the top of a whole-screen task, such as 排序帳戶.
  static const done = ValueKey('flow:done');

  /// 關於's card with the version: tapped, it looks for a newer one.
  static const checkUpdate = ValueKey('update:check');

  /// The switch that keeps backups with photos to Wi-Fi.
  static const photosOnWifi = ValueKey('backup:photos-on-wifi');

  /// 重新選擇 on the folder card, when the folder no longer lets the app
  /// write.
  static const chooseFolderAgain = ValueKey('backup:choose-folder-again');

  /// The update panel's 更新, 晚一點再說 and 略過這一版.
  static const install = ValueKey('update:install');
  static const later = ValueKey('update:later');
  static const skip = ValueKey('update:skip');

  /// The lock screen's choices on the welcome page and back from them.
  static const newBook = ValueKey('lock:new');
  static const restore = ValueKey('lock:restore');
  static const restoreFound = ValueKey('lock:restore-found');
  static const back = ValueKey('lock:back');

  /// The unlock screen's 忘記密碼？.
  static const forgot = ValueKey('lock:forgot');

  /// 安全: the password card, its 變更, and 現在鎖上.
  static const password = ValueKey('security:password');
  static const changePassword = ValueKey('security:change');
  static const lockNow = ValueKey('security:lock-now');

  /// 安全: the backup passphrase card, and 重設金鑰 with its button.
  static const passphrase = ValueKey('security:passphrase');
  static const resetKeys = ValueKey('security:reset-keys');
  static const resetGo = ValueKey('security:reset-go');

  /// The restore form's 還原.
  static const restoreGo = ValueKey('lock:restore-go');

  /// What is drawn over the whole app while the ledger may not be seen.
  static const lockCover = ValueKey('lock:cover');

  /// The lock screen's wait after wrong passwords, counting down.
  static const unlockWait = ValueKey('lock:wait');

  /// The lock screen's fingerprint button.
  static const fingerprint = ValueKey('lock:fingerprint');

  /// 安全: the fingerprint switch, 自動上鎖 and each of its choices, and
  /// 禁止截圖.
  static const fingerprintSwitch = ValueKey('security:fingerprint');
  static const autoLock = ValueKey('security:auto-lock');
  static Key autoLockChoice(String name) =>
      ValueKey('security:auto-lock:$name');
  static const hideScreen = ValueKey('security:hide-screen');

  /// The screen asking for a new password after the recovery code: its
  /// button, and the way to choose no password.
  static const newPassword = ValueKey('keys:new-password');
  static const noPassword = ValueKey('keys:no-password');

  /// A card page's 下次結帳, which moves the next close.
  static const moveClose = ValueKey('card:move-close');

  /// The account form's own broker discount (D7).
  static const accountDiscount = ValueKey('account:broker-discount');

  /// The button of a page with nothing on it (EmptyState), by page.
  static Key emptyAction(String page) => ValueKey('empty:$page');

  /// The tour's 略過.
  static const skipTour = ValueKey('tour:skip');

  /// 取消下載 of an update under way.
  static const cancelDownload = ValueKey('update:cancel-download');
}
