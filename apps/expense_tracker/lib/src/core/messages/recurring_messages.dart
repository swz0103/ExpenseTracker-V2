import '../ledger/ledger.dart';
import '../../../design_system/display/amount.dart';
import '../../../design_system/display/date.dart';
import 'validation_messages.dart';

/// The unit as it follows a count: 「天」「週」「個月」「年」.
String repeatUnitLabel(RepeatUnit unit) => switch (unit) {
  RepeatUnit.day => '天',
  RepeatUnit.week => '週',
  RepeatUnit.month => '個月',
  RepeatUnit.year => '年',
};

/// How often [item] comes round: 「每月 5 日」「每 2 週 週五」「每年 3/15」.
String rhythmOf(Recurring item) {
  final first = item.start;
  final every = item.every;
  final n = every == 1 ? '' : ' $every ';
  final weekday = first == null ? '' : ' ${formatE(first)}';
  final date = first == null ? '' : ' ${formatMd(first)}';
  return switch (item.unit) {
    RepeatUnit.day => '每$n天',
    RepeatUnit.week => '每$n週$weekday',
    RepeatUnit.month => '每$n${every == 1 ? '月' : '個月'} ${item.day} 日',
    RepeatUnit.year => '每$n年$date',
  };
}

/// A confirmation from a notification that the ledger refused to book:
/// 「房租」10/5 沒有入帳：還沒有匯率，請輸入折合台幣的金額.
String inboxRefused(String name, String day, RecordIssue issue) =>
    '「$name」$day 沒有入帳：${validationMessage(issue)}';

/// One item an automatic booking left (D61, R5): 「Netflix」4 期
/// （4/15–7/15）, or why it was not booked by itself.
String heldLine(HeldBooking held) {
  final name = held.item.name;
  final first = formatMd(held.days.first);
  if (held.closed) return '「$name」的帳戶已封存，$first 起沒有自動入帳';
  if (held.refusal case final refusal?) {
    return '「$name」$first 沒有自動入帳：${validationMessage(refusal)}';
  }
  final count = held.days.length;
  return count == 1
      ? '「$name」$first'
      : '「$name」$count 期（$first–${formatMd(held.days.last)}）';
}

/// The question asked before booking what was left to confirm (D61).
const heldTitle = '有定期交易多期尚未入帳';

/// What [heldTitle] asks about, one line an item; at most
/// [RecurringCommands.bookedAtOnce] days of an item are booked at once.
String heldBody(List<HeldBooking> held) => [
  for (final h in held) heldLine(h),
  '確認後各期記在自己的日期；不確認的話，可到「定期交易」逐期入帳',
].join('\n');

/// The yes of [heldTitle].
const heldConfirm = '全部入帳';

/// What was booked by itself as the ledger opened or came back.
String autoBooked(int count) =>
    '已自動記下 ${countOf(count, CountUnit.entries)}定期交易';

/// What was booked once the person confirmed: 已記下 3 筆定期交易.
String heldBooked(int count) => '已記下 ${countOf(count, CountUnit.entries)}定期交易';

/// What could not be booked by itself, told once.
const heldRefusedTitle = '定期交易未自動入帳';
