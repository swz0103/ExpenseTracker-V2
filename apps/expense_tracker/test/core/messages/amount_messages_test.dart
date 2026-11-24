import 'package:expense_tracker/src/core/messages/amount_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    "R5: a day gone by valued at today's rate is said to be an estimate",
    () {
      expect(estimatedAtTodaysRate(32.5), '以今日臺銀即期買入 32.5 估算，請改成當日金額');
    },
  );
}
