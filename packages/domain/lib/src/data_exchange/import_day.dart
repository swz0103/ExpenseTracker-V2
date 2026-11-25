import 'package:core/foundation_values.dart'
    show BusinessDate, daysInMonth, rocYearOffset;

/// The earliest year a date read from an imported file may be in
/// (decision D93): an earlier one is a year misread, such as a
/// Republic of China year taken for a Gregorian one, never a record.
const earliestImportYear = 1950;

/// Why a text is not a day of an imported file.
enum DayProblem {
  /// Not a date at all, or not one of the calendar (Feb 30).
  unreadable,

  /// A year of one or two digits (`26/10/01`): it could be 2026 or the
  /// Republic of China's 26 (1937), so it is not guessed at (D93).
  shortYear,

  /// Before [earliestImportYear] (D93).
  tooEarly,

  /// After the last day an entry may be dated (`latest` of
  /// [readImportDay]): a year misread, such as ROC 999 for 2910 (r13 F6).
  tooLate,
}

/// A day read from an imported file, or why it could not be.
sealed class ImportDay {
  const ImportDay();
}

final class DayRead extends ImportDay {
  const DayRead(this.date);

  final BusinessDate date;
}

final class DayRefused extends ImportDay {
  const DayRefused(this.problem);

  final DayProblem problem;
}

/// The day [text] writes, by decision D93: a year of four digits is
/// Gregorian (2026-03-05, 2026/3/5, 2026.3.5, 20260305), one of three is
/// the Republic of China's (115/3/5, 1150305), one of one or two is
/// refused as [DayProblem.shortYear], a day before
/// [earliestImportYear] as [DayProblem.tooEarly], and one after [latest],
/// the last day an entry written today may be dated, as
/// [DayProblem.tooLate].
ImportDay readImportDay(String text, {BusinessDate? latest}) {
  final value = text.trim();
  final String year;
  final String month;
  final String day;
  final compact = _compact.firstMatch(value);
  if (compact != null) {
    (year, month, day) = (compact[1]!, compact[2]!, compact[3]!);
  } else {
    final parts = _separated.firstMatch(value);
    if (parts == null) return const DayRefused(DayProblem.unreadable);
    (year, month, day) = (parts[1]!, parts[2]!, parts[3]!);
  }
  if (year.length < 3) return const DayRefused(DayProblem.shortYear);
  final written = int.parse(year);
  final gregorian = year.length == 3 ? written + rocYearOffset : written;
  final m = int.parse(month);
  final d = int.parse(day);
  if (m < 1 || m > 12 || d < 1 || d > daysInMonth(gregorian, m)) {
    return const DayRefused(DayProblem.unreadable);
  }
  if (gregorian < earliestImportYear) {
    return const DayRefused(DayProblem.tooEarly);
  }
  final date = BusinessDate(gregorian, m, d);
  if (latest != null && date.compareTo(latest) > 0) {
    return const DayRefused(DayProblem.tooLate);
  }
  return DayRead(date);
}

/// 20260305, 1150305 and 261005: the year, then two digits each of the
/// month and the day.
final _compact = RegExp(r'^(\d{2,4})(\d{2})(\d{2})$');

/// 2026-03-05, 2026/3/5, 115.3.5, 26/10/01.
final _separated = RegExp(r'^(\d{1,4})[-/.](\d{1,2})[-/.](\d{1,2})$');
