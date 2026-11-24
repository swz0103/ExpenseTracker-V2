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

  group('D61: what was left to confirm', () {
    const rent = Recurring(
      id: 'rent',
      name: '房租',
      amount: 1,
      day: 5,
      account: 'bank',
      category: '居家',
    );
    final days = [
      DateTime.utc(2026, 9, 5),
      DateTime.utc(2026, 10, 5),
      DateTime.utc(2026, 11, 5),
    ];

    test('one line an item', () {
      expect(heldLine(HeldBooking(rent, days)), '「房租」3 期（9/5–11/5）');
      expect(heldLine(HeldBooking(rent, days.sublist(2))), '「房租」11/5');
      expect(
        heldLine(HeldBooking(rent, days, closed: true)),
        '「房租」的帳戶已封存，9/5 起沒有自動入帳',
      );
      expect(
        heldLine(
          HeldBooking(
            rent,
            days.sublist(0, 1),
            refusal: const MissingHomeAmount(),
          ),
        ),
        startsWith('「房租」9/5 沒有自動入帳：'),
      );
    });

    test('the question and its body', () {
      expect(heldBody([HeldBooking(rent, days)]).split('\n'), [
        '「房租」3 期（9/5–11/5）',
        '確認後各期記在自己的日期；不確認的話，可到「定期交易」逐期入帳',
      ]);
      expect(heldTitle, '有定期交易多期尚未入帳');
      expect(heldRefusedTitle, '定期交易未自動入帳');
      expect(heldConfirm, '全部入帳');
      expect(heldBooked(3), '已記下 3 筆定期交易');
    });
  });
}
