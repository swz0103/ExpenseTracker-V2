import 'calendar_day.dart';

/// The day weeks start on, as Taiwan's calendars print them: Sunday.
const firstDayOfWeek = DateTime.sunday;

/// [date]'s place in the week: 0 for [firstDayOfWeek] to 6.
int weekdayIndex(BusinessDate date) =>
    (date.weekday - firstDayOfWeek) % DateTime.daysPerWeek;

/// [DateTime.weekday] of the day at [index] (0 to 6) of the week.
int weekdayAt(int index) =>
    (firstDayOfWeek - 1 + index) % DateTime.daysPerWeek + 1;

/// The day the week of [date] starts on.
BusinessDate startOfWeek(BusinessDate date) =>
    date.addDays(-weekdayIndex(date));
