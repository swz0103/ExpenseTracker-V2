import 'package:expense_tracker/src/core/messages/amount_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    "R5: a day gone by valued at today's rate is said to be an estimate",
    () {
      expect(estimatedAtTodaysRate(32.5), '以今日臺銀即期買入 32.5 估算，請改成當日金額');
      // D118: a whole rate has no trailing .0.
      expect(estimatedAtTodaysRate(32.0), '以今日臺銀即期買入 32 估算，請改成當日金額');
      expect(todaysRate(32.0), '臺銀即期買入 32');
      expect(todaysRate(0.2105), '臺銀即期買入 0.2105');
    },
  );

  test('D58: a rate kept for a day names its board\'s day', () {
    final today = DateTime.utc(2026, 11, 25);
    expect(
      rateOfDay(32.5, DateTime.utc(2026, 11, 20), today: today),
      '臺銀 11/20 即期買入 32.5',
    );
    expect(
      rateOfDay(30.0, DateTime.utc(2025, 3, 9), today: today),
      '臺銀 2025/3/9 即期買入 30',
    );
  });
}
