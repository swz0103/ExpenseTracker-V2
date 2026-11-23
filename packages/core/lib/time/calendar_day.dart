import 'month_arithmetic.dart';
import 'year_month.dart';

/// A civil calendar date with no timezone or implied midnight instant.
final class BusinessDate implements Comparable<BusinessDate> {
  BusinessDate(this.year, this.month, this.day) {
    if (year < 1 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > daysInMonth(year, month)) {
      throw const FormatException('Invalid business date.');
    }
  }
  factory BusinessDate.parse(String text) {
    if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(text)) {
      throw const FormatException('Expected YYYY-MM-DD.');
    }
    return BusinessDate(
      int.parse(text.substring(0, 4)),
      int.parse(text.substring(5, 7)),
      int.parse(text.substring(8, 10)),
    );
  }

  /// The calendar day of [value] as its own fields read, whatever zone
  /// it is in: the caller decides the zone before handing it over.
  factory BusinessDate.of(DateTime value) =>
      BusinessDate(value.year, value.month, value.day);

  final int year;
  final int month;
  final int day;

  /// [DateTime.monday] (1) to [DateTime.sunday] (7).
  int get weekday => DateTime.utc(year, month, day).weekday;

  /// Whether it is a Saturday or a Sunday.
  bool get isWeekend =>
      weekday == DateTime.saturday || weekday == DateTime.sunday;

  /// The year and month it falls in.
  YearMonth get yearMonth => YearMonth(year, month);

  /// The day [days] later (earlier when negative).
  BusinessDate addDays(int days) =>
      BusinessDate.of(DateTime.utc(year, month, day + days));

  /// How many days from this date to [other] (negative when earlier).
  int daysUntil(BusinessDate other) =>
      other.asUtcMidnight.difference(asUtcMidnight).inDays;

  /// The date as a UTC midnight, the form the app's screens hold days in.
  DateTime get asUtcMidnight => DateTime.utc(year, month, day);

  bool isBefore(BusinessDate other) => compareTo(other) < 0;
  bool isAfter(BusinessDate other) => compareTo(other) > 0;

  /// `YYYY-MM-DD`, the form dates are stored and exchanged in.
  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${twoDigits(month)}-${twoDigits(day)}';

  /// `YYYYMMDD`, as in file names.
  String get compact =>
      '${year.toString().padLeft(4, '0')}${twoDigits(month)}${twoDigits(day)}';

  @override
  int compareTo(BusinessDate other) => toString().compareTo(other.toString());
  @override
  bool operator ==(Object other) =>
      other is BusinessDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;
  @override
  int get hashCode => Object.hash(year, month, day);
}

/// [n] with a leading zero below ten, as in dates and clock times written
/// for machines (`2026-01-05`, `09:05`).
String twoDigits(int n) => n.toString().padLeft(2, '0');
