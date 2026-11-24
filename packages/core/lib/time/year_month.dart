import 'calendar_day.dart';
import 'month_arithmetic.dart';

/// A month of a year, such as October 2026: what budgets, reports and
/// statements are kept by.
final class YearMonth implements Comparable<YearMonth> {
  YearMonth(this.year, this.month) {
    if (year < 1 || year > 9999 || month < 1 || month > 12) {
      throw const FormatException('Invalid year and month.');
    }
  }

  /// The month [value]'s own fields fall in.
  factory YearMonth.of(DateTime value) => YearMonth(value.year, value.month);

  final int year;
  final int month;

  /// The month [months] later (earlier when negative).
  YearMonth addMonths(int months) {
    final (y, m) = shiftMonth(year, month, months);
    return YearMonth(y, m);
  }

  YearMonth get next => addMonths(1);
  YearMonth get previous => addMonths(-1);

  int get days => daysInMonth(year, month);
  BusinessDate get firstDay => BusinessDate(year, month, 1);
  BusinessDate get lastDay => BusinessDate(year, month, days);

  /// How many months from this one to [other] (negative when earlier).
  int monthsUntil(YearMonth other) =>
      (other.year - year) * 12 + other.month - month;

  bool contains(BusinessDate date) => date.year == year && date.month == month;

  /// The first day as a UTC midnight, as the screens hold months.
  DateTime get asUtcMidnight => DateTime.utc(year, month);

  /// `YYYY-MM`, the form months are stored and exchanged in.
  @override
  String toString() => '${year.toString().padLeft(4, '0')}-${twoDigits(month)}';

  @override
  int compareTo(YearMonth other) => monthsUntil(other) == 0
      ? 0
      : monthsUntil(other) > 0
      ? -1
      : 1;

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}
