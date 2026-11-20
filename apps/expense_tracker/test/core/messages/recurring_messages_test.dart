import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/messages/recurring_messages.dart';
import 'package:flutter_test/flutter_test.dart';

Recurring _item(RepeatUnit unit, {int every = 1, DateTime? start}) => Recurring(
  id: 'r',
  name: 'r',
  amount: 1,
  day: 5,
  account: 'bank',
  category: '居家',
  unit: unit,
  every: every,
  start: start,
);

void main() {
  final friday = DateTime.utc(2026, 3, 13);

  test('each unit has its words', () {
    expect(
      [for (final u in RepeatUnit.values) repeatUnitLabel(u)],
      ['天', '週', '個月', '年'],
    );
  });

  test('how often an item comes round reads as people say it', () {
    expect(rhythmOf(_item(RepeatUnit.month)), '每月 5 日');
    expect(rhythmOf(_item(RepeatUnit.month, every: 3)), '每 3 個月 5 日');
    expect(
      rhythmOf(_item(RepeatUnit.week, every: 2, start: friday)),
      '每 2 週 週五',
    );
    expect(rhythmOf(_item(RepeatUnit.year, start: friday)), '每年 3/13');
    expect(rhythmOf(_item(RepeatUnit.day, every: 10)), '每 10 天');
  });
}
