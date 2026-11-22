/// Calendar arithmetic on plain numbers: leap years, month lengths and
/// moving by months with the day kept inside the month.
library;

/// Whether [year] has a 29 February (Gregorian rule).
bool isLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

/// How many days [month] of [year] has.
int daysInMonth(int year, int month) => switch (month) {
  2 => isLeapYear(year) ? 29 : 28,
  4 || 6 || 9 || 11 => 30,
  _ => 31,
};

/// The year and month [months] after [year]/[month] (before when
/// negative).
(int, int) shiftMonth(int year, int month, int months) {
  final index = year * 12 + (month - 1) + months;
  return (index ~/ 12, index % 12 + 1);
}

/// [day] of the month [months] after [year]/[month], held to that month's
/// last day: 31 January plus one month is 28 (or 29) February.
(int, int, int) addMonthsClamped(int year, int month, int day, int months) {
  final (y, m) = shiftMonth(year, month, months);
  final last = daysInMonth(y, m);
  return (y, m, day > last ? last : day);
}
