import 'package:expense_tracker/src/core/messages/reminder_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('F53: how late a reminder may come is said in hours', () {
    expect(ReminderMessages.lateBy(const Duration(hours: 1)), '最多晚 1 小時');
    expect(
      ReminderMessages.lateWithout(const Duration(hours: 1)),
      '未開啟時可能延後，最多晚 1 小時',
    );
  });

  test('nothing due within the plan says how far it looks', () {
    expect(ReminderMessages.nothingDueWithin(62), '62 天內沒有到期的項目');
  });
}
