import '../../../design_system/display/amount.dart';

/// What a note says once a change is made (D82): every deletion,
/// archive, merge, import and budget taken away is told on screen; one
/// that can be undone is told with 復原 (`showUndo`), and is not asked
/// first.
abstract final class DoneWords {
  /// [name], an entry, account, person, recurring item or tag, deleted.
  static String deleted(String name) => '已刪除「$name」';

  /// An entry of a recurring item deleted: its period is let go.
  static String deletedBooking(String title) => '已刪除「$title」，這一期跳過';

  /// Several entries deleted at once.
  static String deletedEntries(int count) =>
      '已刪除 ${countOf(count, CountUnit.entries)}';

  static String archived(String name) => '已封存「$name」';
  static String unarchived(String name) => '已恢復「$name」';

  /// One category, tag or merchant merged into another.
  static String merged(String from, String into) => '已把「$from」合併到「$into」';

  /// A tag or merchant given another name.
  static String renamed(String from, String to) => '已把「$from」改成「$to」';

  /// The budget on [name] taken away.
  static String budgetDeleted(String name) => '已刪除「$name」的額度';

  static String imported(int count) =>
      '已匯入 ${countOf(count, CountUnit.entries)}紀錄';
}
