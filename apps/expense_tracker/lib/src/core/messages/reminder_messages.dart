import '../../../design_system/display/amount.dart';
import '../../../design_system/display/status_messages.dart';

/// The words of the reminders: the names the phone's settings show for
/// each kind of notification, the test notification, and what the
/// reminder settings say about lateness, the calendar and the battery.
abstract final class ReminderMessages {
  /// The notification channels, as the phone's settings list them.
  static const dueChannel = '到期提醒';
  static const dueChannelAbout = '定期扣款、卡費到期';
  static const nudgeChannel = '每日記帳提醒';
  static const nudgeChannelAbout = '當天還沒記帳時提醒';
  static const budgetChannel = '預算提醒';
  static const budgetChannelAbout = '預算用到警示比例或${StatusWords.over}時';

  /// The test notification 試一則 sends.
  static const testTitle = '測試通知';
  static const testText = '提醒會像這樣出現';

  /// The daily nudge.
  static const nudgeTitle = '今天記帳了嗎？';
  static const nudgeText = '點一下記一筆';

  /// How late a reminder may come when alarms on the minute are off or
  /// not allowed: 「最多晚 1 小時」.
  static String lateBy(Duration lateness) =>
      '最多晚 ${countOf(lateness.inHours, CountUnit.hours)}';

  /// Under 準時提醒 while it is off: what to expect without it.
  static String lateWithout(Duration lateness) =>
      '未開啟時可能延後，${lateBy(lateness)}';

  /// 到期提醒's details with nothing coming: 「62 天內沒有到期的項目」.
  static String nothingDueWithin(int days) =>
      '${countOf(days, CountUnit.days)}內沒有到期的項目';

  /// The Google 日曆 card and its details.
  static const calendarTitle = 'Google 日曆';
  static const calendarAbout = '提醒定期扣款與卡費';
  static String calendarSyncedTo(String name) => '同步到「$name」';
  static const calendarPick = '同步到哪個日曆';
  static const calendarAmounts = '寫入金額';
  static const calendarAmountsOn = '例：繳卡費：玉山卡 12,345';
  static const calendarAmountsOff = '例：繳卡費：玉山卡';
  static const calendarChange = '換日曆';
  static const calendarStop = '不再同步';

  /// Linking a calendar: what came of it.
  static const calendarNoAccess = '沒有取得日曆權限，可以到系統設定開啟';
  static const calendarNone = '手機上沒有可寫入的日曆，請先在日曆 App 登入 Google 帳號';
  static const calendarNotSynced = '日曆沒有同步成功';
  static String calendarWritten(int count) =>
      '已把 ${countOf(count, CountUnit.pieces)}到期提醒放進日曆';
  static const calendarUnreachable = '日曆沒有連上';

  /// 不再同步 when the app's events could be taken off the calendar.
  static const calendarCleared = '已停止同步，之後的提醒已從日曆刪除';

  /// 不再同步 when they could not (calendar access turned off): the link
  /// is dropped all the same.
  static const calendarLeft = '已停止同步；日曆無法存取，已寫入的提醒請到日曆 App 刪除';

  /// After 去開 for the battery: the app's own page opens, where the
  /// person picks the setting.
  static const batteryHow = '請在「電池」選「不受限制」，提醒才不會被延後';
}
