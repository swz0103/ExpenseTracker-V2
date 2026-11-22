import '../calendar_day.dart';

/// Which days banks and the stock exchange are open: weekdays, except
/// [holidays], plus weekend [workdays] that make up for a holiday.
/// Taiwan's official days come from `taiwanHolidays.banking`.
final class BankingCalendar {
  BankingCalendar({
    Set<BusinessDate> holidays = const {},
    Set<BusinessDate> workdays = const {},
  }) : holidays = Set.unmodifiable(holidays),
       workdays = Set.unmodifiable(workdays);

  final Set<BusinessDate> holidays;
  final Set<BusinessDate> workdays;

  bool isOpen(BusinessDate date) {
    if (workdays.contains(date)) return true;
    return !date.isWeekend && !holidays.contains(date);
  }

  /// [date] when open, otherwise the next open day.
  BusinessDate onOrAfter(BusinessDate date) {
    var day = date;
    for (var i = 0; i < 60; i++) {
      if (isOpen(day)) return day;
      day = day.addDays(1);
    }
    throw StateError('No open day within 60 days of $date.');
  }

  /// The [count]th open day after [date], as in T+2 settlement.
  BusinessDate addOpenDays(BusinessDate date, int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    var day = date;
    for (var left = count; left > 0;) {
      day = onOrAfter(day.addDays(1));
      left--;
    }
    return day;
  }
}
