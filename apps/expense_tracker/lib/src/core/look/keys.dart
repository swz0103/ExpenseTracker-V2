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

  /// The composer's main button: 記下支出, 記下代墊 and the like.
  static const save = ValueKey('compose:save');

  /// The composer's 刪除 (an entry looked at) or 暫存 (a new one).
  static const discard = ValueKey('compose:discard');

  /// The yes of a question asked before something is done, such as 刪除.
  static const confirm = ValueKey('dialog:confirm');

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

  /// The update panel's 更新, 晚一點再說 and 略過這一版.
  static const install = ValueKey('update:install');
  static const later = ValueKey('update:later');
  static const skip = ValueKey('update:skip');

  /// The lock screen's choices on the welcome page and back from them.
  static const newBook = ValueKey('lock:new');
  static const restore = ValueKey('lock:restore');
  static const restoreFound = ValueKey('lock:restore-found');
  static const back = ValueKey('lock:back');

  /// 安全: the password card, its 變更, and 現在鎖上.
  static const password = ValueKey('security:password');
  static const changePassword = ValueKey('security:change');
  static const lockNow = ValueKey('security:lock-now');
}
