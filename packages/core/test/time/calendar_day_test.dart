import 'package:core/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  test('business dates validate leap years rather than normalize overflow', () {
    for (final value in [
      '2000-02-29',
      '2024-02-29',
      '2026-09-26',
      '0001-01-01',
      '9999-12-31',
    ]) {
      expect(BusinessDate.parse(value).toString(), value);
    }
    for (final value in [
      '1900-02-29',
      '2026-02-29',
      '2026-04-31',
      '2026-13-01',
      '0000-01-01',
      '2026-01-00',
      '2026-9-26',
      '2026-09-26Z',
    ]) {
      expect(() => BusinessDate.parse(value), throwsFormatException);
    }
  });
  test('date ordering follows calendar and does not infer a timezone', () {
    final dates = [
      '2027-01-01',
      '2026-12-31',
      '2024-02-29',
    ].map(BusinessDate.parse).toList()..sort();
    expect(dates.map((date) => date.toString()), [
      '2024-02-29',
      '2026-12-31',
      '2027-01-01',
    ]);
    expect(BusinessDate.parse('2026-09-26'), BusinessDate(2026, 9, 26));
  });
  test('weekday, weekend, adding days and counting between', () {
    // 2026-10-10 is a Saturday.
    final saturday = BusinessDate(2026, 10, 10);
    expect(saturday.weekday, DateTime.saturday);
    expect(saturday.isWeekend, isTrue);
    expect(BusinessDate(2026, 10, 9).isWeekend, isFalse);
    // 2026-12-31 + 1 day = 2027-01-01.
    expect(BusinessDate(2026, 12, 31).addDays(1), BusinessDate(2027, 1, 1));
    // 2024 is a leap year: 2024-02-28 + 1 = 02-29.
    expect(BusinessDate(2024, 2, 28).addDays(1), BusinessDate(2024, 2, 29));
    // 2026-01-08 to 2026-11-22: 23 + 28 + 31 + 30 + 31 + 30 + 31 + 31
    // + 30 + 31 + 22 = 318.
    expect(BusinessDate(2026, 1, 8).daysUntil(BusinessDate(2026, 11, 22)), 318);
    expect(BusinessDate(2026, 1, 8).yearMonth, YearMonth(2026, 1));
    expect(BusinessDate(2026, 1, 8).compact, '20260108');
    expect(BusinessDate(2026, 1, 8).asUtcMidnight, DateTime.utc(2026, 1, 8));
    expect(
      BusinessDate.of(DateTime(2026, 3, 4, 23, 59)),
      BusinessDate(2026, 3, 4),
    );
    expect(BusinessDate(2026, 3, 4).isBefore(BusinessDate(2026, 3, 5)), isTrue);
    expect(BusinessDate(2026, 3, 4).isAfter(BusinessDate(2026, 3, 5)), isFalse);
    expect(twoDigits(5), '05');
    expect(twoDigits(12), '12');
  });
}
