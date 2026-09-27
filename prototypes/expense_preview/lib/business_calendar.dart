import 'package:flutter/material.dart';

/// UTC here is only a carrier for civil year/month/day, never an event instant.
/// Local midnight may be skipped by a timezone change, so every calendar
/// operation must construct components without consulting the device timezone.
class BusinessCalendar extends GregorianCalendarDelegate {
  const BusinessCalendar();

  @override
  DateTime now() => dateOnly(DateTime.now());
  @override
  DateTime dateOnly(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);
  @override
  DateTime getMonth(int year, int month) => DateTime.utc(year, month);
  @override
  DateTime getDay(int year, int month, int day) =>
      DateTime.utc(year, month, day);
  @override
  DateTime addMonthsToMonthDate(DateTime monthDate, int monthsToAdd) =>
      DateTime.utc(monthDate.year, monthDate.month + monthsToAdd);
  @override
  DateTime addDaysToDate(DateTime date, int days) =>
      DateTime.utc(date.year, date.month, date.day + days);
  @override
  int firstDayOffset(
    int year,
    int month,
    MaterialLocalizations localizations,
  ) =>
      (DateTime.utc(year, month).weekday % 7 -
          localizations.firstDayOfWeekIndex +
          7) %
      7;
  @override
  String formatYear(int year, MaterialLocalizations localizations) =>
      localizations.formatYear(DateTime.utc(year));
}
