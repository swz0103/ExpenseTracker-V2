import '../calendar_day.dart';
import 'banking_calendar.dart';
import 'taiwan_calendar_data.dart';

/// An answer about business days: [Verified] when every day it looked at
/// is in a year of the official calendar, otherwise [WeekendsOnly], worked
/// out from weekends alone, for the caller to say so.
sealed class BusinessDayAnswer<T> {
  const BusinessDayAnswer(this.value);

  /// The answer; for [WeekendsOnly] counted with weekends only.
  final T value;
}

final class Verified<T> extends BusinessDayAnswer<T> {
  const Verified(super.value);
}

/// [year] is not in the calendar, so holidays and make-up workdays in it
/// are unknown and [value] only skips weekends.
final class WeekendsOnly<T> extends BusinessDayAnswer<T> {
  const WeekendsOnly(super.value, this.year);

  final int year;
}

/// Which days are business days: weekdays, except the listed holidays,
/// plus the listed make-up workdays, for the [years] the list covers.
final class HolidayCalendar {
  HolidayCalendar({
    required Set<int> years,
    required Map<BusinessDate, String> holidays,
    required Map<BusinessDate, String> workdays,
  }) : years = Set.unmodifiable(years),
       holidays = Map.unmodifiable(holidays),
       workdays = Map.unmodifiable(workdays);

  /// Reads a table in the form of [taiwanCalendarTable].
  factory HolidayCalendar.parse(String table) {
    final years = <int>{};
    final holidays = <BusinessDate, String>{};
    final workdays = <BusinessDate, String>{};
    for (final raw in table.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('years:')) {
        years.addAll(line.substring(6).split(',').map(int.parse));
        continue;
      }
      final [date, kind, name] = line.split(',');
      final day = BusinessDate.parse(date);
      switch (kind) {
        case 'holiday':
          holidays[day] = name;
        case 'workday':
          workdays[day] = name;
        default:
          throw FormatException('Unknown kind of day: $kind');
      }
    }
    return HolidayCalendar(
      years: years,
      holidays: holidays,
      workdays: workdays,
    );
  }

  /// The years whose holidays are known.
  final Set<int> years;

  /// Weekdays off, with their names.
  final Map<BusinessDate, String> holidays;

  /// Weekend days worked, with their names.
  final Map<BusinessDate, String> workdays;

  bool _open(BusinessDate date) =>
      workdays.containsKey(date) ||
      (!date.isWeekend && !holidays.containsKey(date));

  /// Whether banks and offices are open on [date].
  BusinessDayAnswer<bool> isBusinessDay(BusinessDate date) =>
      _answer(_open(date), [date]);

  /// The first business day after [date].
  BusinessDayAnswer<BusinessDate> nextBusinessDay(BusinessDate date) =>
      _walk(date, 1, 1);

  /// The last business day before [date].
  BusinessDayAnswer<BusinessDate> previousBusinessDay(BusinessDate date) =>
      _walk(date, -1, 1);

  /// [date] when it is a business day, otherwise the next one: where a due
  /// date that falls on a day off moves to.
  BusinessDayAnswer<BusinessDate> onOrAfter(BusinessDate date) =>
      _open(date) ? _answer(date, [date]) : nextBusinessDay(date);

  /// The [count]th business day after [date], as in T+2 settlement.
  BusinessDayAnswer<BusinessDate> addBusinessDays(
    BusinessDate date,
    int count,
  ) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    return count == 0 ? _answer(date, [date]) : _walk(date, 1, count);
  }

  /// This calendar as the [BankingCalendar] the trade rules take.
  BankingCalendar get banking => BankingCalendar(
    holidays: holidays.keys.toSet(),
    workdays: workdays.keys.toSet(),
  );

  BusinessDayAnswer<BusinessDate> _walk(
    BusinessDate date,
    int step,
    int count,
  ) {
    final seen = [date];
    var day = date;
    for (var left = count; left > 0;) {
      day = day.addDays(step);
      seen.add(day);
      if (_open(day)) left--;
    }
    return _answer(day, seen);
  }

  BusinessDayAnswer<T> _answer<T>(T value, List<BusinessDate> seen) {
    for (final day in seen) {
      if (!years.contains(day.year)) return WeekendsOnly(value, day.year);
    }
    return Verified(value);
  }
}

/// Taiwan's official calendar, from [taiwanCalendarTable].
final taiwanHolidays = HolidayCalendar.parse(taiwanCalendarTable);
