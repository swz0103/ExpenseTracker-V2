import 'package:expense_tracker/src/app/android/calendar_adapter.dart';
import 'package:expense_tracker/src/features/reminders/model/calendar_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an event goes to the phone with its id when it has one', () {
    final event = CalendarEvent(
      key: 'r:gym:2026-12-5',
      title: '扣款：健身房',
      note: '定期交易',
      start: DateTime(2026, 12, 5, 9),
      remind: const [0, 2880],
    );
    final fields = AndroidCalendar.eventFields(event)..remove('start');
    expect(fields, {
      'key': 'r:gym:2026-12-5',
      'title': '扣款：健身房',
      'note': '定期交易',
      'remind': [0, 2880],
    });
    expect(AndroidCalendar.eventFields(event.replacing(42))['id'], 42);
  });
}
