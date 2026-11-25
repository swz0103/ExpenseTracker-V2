import 'package:core/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  test('weeks start on Sunday', () {
    expect(firstDayOfWeek, DateTime.sunday);
    // 2026-10-04 is a Sunday, 10-10 a Saturday.
    expect(weekdayIndex(BusinessDate(2026, 10, 4)), 0);
    expect(weekdayIndex(BusinessDate(2026, 10, 5)), 1);
    expect(weekdayIndex(BusinessDate(2026, 10, 10)), 6);
    expect(startOfWeek(BusinessDate(2026, 10, 10)), BusinessDate(2026, 10, 4));
    expect(startOfWeek(BusinessDate(2026, 10, 4)), BusinessDate(2026, 10, 4));
    // Thursday 2026-10-01 → Sunday 2026-09-27, across a month.
    expect(startOfWeek(BusinessDate(2026, 10, 1)), BusinessDate(2026, 9, 27));
  });

  test('the weekday at each place of the week', () {
    expect(weekdayAt(0), DateTime.sunday);
    expect(weekdayAt(1), DateTime.monday);
    expect(weekdayAt(6), DateTime.saturday);
  });
}
