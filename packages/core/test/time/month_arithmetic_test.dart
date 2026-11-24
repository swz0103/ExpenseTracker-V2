import 'package:core/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  test('leap years follow the Gregorian rule', () {
    expect(isLeapYear(2024), isTrue);
    expect(isLeapYear(2026), isFalse);
    expect(isLeapYear(1900), isFalse);
    expect(isLeapYear(2000), isTrue);
  });

  test('dates run from year 1 to year 9999', () {
    expect((minYear, maxYear), (1, 9999));
    expect(BusinessDate(maxYear, 12, 31).toString(), '9999-12-31');
    expect(() => BusinessDate(maxYear + 1, 1, 1), throwsFormatException);
    expect(() => YearMonth(minYear - 1, 12), throwsFormatException);
  });

  test('a month index orders months and counts the months between', () {
    // 2026 * 12 + (11 - 1) = 24322.
    expect(monthIndex(2026, 11), 24322);
    // December 2025 to February 2027: 14 months.
    expect(monthIndex(2027, 2) - monthIndex(2025, 12), 14);
    expect(monthIndex(2027, 1) > monthIndex(2026, 12), isTrue);
  });

  test('month lengths', () {
    expect(daysInMonth(2026, 1), 31);
    expect(daysInMonth(2026, 2), 28);
    expect(daysInMonth(2028, 2), 29);
    expect(daysInMonth(2026, 9), 30);
    expect(daysInMonth(2026, 12), 31);
  });

  test('shifting months crosses years both ways', () {
    expect(shiftMonth(2026, 11, 2), (2027, 1));
    expect(shiftMonth(2026, 1, -1), (2025, 12));
    expect(shiftMonth(2026, 1, -13), (2024, 12));
  });

  test('adding months keeps the day inside the month', () {
    // 31 Jan + 1 month: February 2026 has 28 days.
    expect(addMonthsClamped(2026, 1, 31, 1), (2026, 2, 28));
    // 31 Jan 2028 + 1 month: leap February.
    expect(addMonthsClamped(2028, 1, 31, 1), (2028, 2, 29));
    // 31 Mar - 1 month = 28 Feb.
    expect(addMonthsClamped(2026, 3, 31, -1), (2026, 2, 28));
    expect(addMonthsClamped(2026, 3, 15, 12), (2027, 3, 15));
  });
}
