import 'package:core/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  test('every row of the table is a weekday off or a weekend worked', () {
    for (final day in taiwanHolidays.holidays.keys) {
      expect(day.isWeekend, isFalse, reason: '$day');
      expect(taiwanHolidays.years, contains(day.year));
    }
    for (final day in taiwanHolidays.workdays.keys) {
      expect(day.isWeekend, isTrue, reason: '$day');
      expect(taiwanHolidays.years, contains(day.year));
    }
  });

  test('fixed national holidays are on their dates', () {
    // New Year's Day 2026 and 2027 fall on weekdays.
    expect(taiwanHolidays.holidays[BusinessDate(2026, 1, 1)], '開國紀念日');
    expect(taiwanHolidays.holidays[BusinessDate(2027, 1, 1)], '開國紀念日');
    expect(taiwanHolidays.holidays[BusinessDate(2026, 12, 25)], '行憲紀念日');
  });
}
