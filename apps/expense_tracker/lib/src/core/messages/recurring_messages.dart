import '../ledger/ledger.dart';
import '../../../design_system/display/date.dart';

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
    RepeatUnit.month =>
      '每$n${every == 1 ? '月' : '個月'} ${first?.day ?? item.day} 日',
    RepeatUnit.year => '每$n年$date',
  };
}
