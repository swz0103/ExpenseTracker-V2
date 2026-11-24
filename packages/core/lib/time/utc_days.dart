/// Days and months as the app holds them: a [DateTime] at UTC midnight.
/// Arithmetic on a value's own fields only; no time zone or clock is read.
library;

import 'month_arithmetic.dart';

/// [value]'s own year, month and day at UTC midnight: the day a moment,
/// or a day held some other way, falls on.
DateTime dayOf(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

/// The first day of the month [months] after [value]'s (before when
/// negative).
DateTime monthStart(DateTime value, [int months = 0]) {
  final (y, m) = shiftMonth(value.year, value.month, months);
  return DateTime.utc(y, m);
}

/// The last day of [year]/[month]. A [month] past 12 or below 1 runs on
/// into the next year or back into an earlier one.
DateTime monthEnd(int year, int month) {
  final (y, m) = shiftMonth(year, month, 0);
  return DateTime.utc(y, m, daysInMonth(y, m));
}

/// The first day of each month from [from]'s to the last that starts on
/// or before [to], earliest first; none when [to] is before [from]'s
/// month.
Iterable<DateTime> monthStarts(DateTime from, DateTime to) sync* {
  for (var m = monthStart(from); !m.isAfter(to); m = monthStart(m, 1)) {
    yield m;
  }
}

/// [day]'s day of the month [months] after its own (before when
/// negative), at UTC midnight, held to that month's last day: 31 March
/// one month back is 28 (or 29) February, never 3 March.
DateTime monthsAfter(DateTime day, int months) {
  final (y, m, d) = addMonthsClamped(day.year, day.month, day.day, months);
  return DateTime.utc(y, m, d);
}

/// The same day a year earlier, at UTC midnight; 29 February becomes the
/// 28th.
DateTime yearBefore(DateTime day) => monthsAfter(day, -12);
