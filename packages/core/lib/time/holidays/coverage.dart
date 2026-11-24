import '../calendar_day.dart';
import 'business_days.dart';

/// How many days before the last day a holiday table covers its guard
/// starts to fail, so the next year's rows are added before the table
/// runs out (D33). The one number for every such table.
const holidayTableLeadDays = 60;

/// Where a holiday table stands on a day: covering it for long enough,
/// or running out.
sealed class HolidayCoverage {
  const HolidayCoverage();
}

/// The table covers every day up to [until], more than
/// [holidayTableLeadDays] away.
final class CoverageAhead extends HolidayCoverage {
  const CoverageAhead(this.until);

  final BusinessDate until;
}

/// The table runs out on [until], [daysLeft] days away (none or fewer
/// when it already has): its next year is due. [until] is null when the
/// table does not cover the day's own year at all.
final class CoverageEnding extends HolidayCoverage {
  const CoverageEnding(this.until, this.daysLeft);

  final BusinessDate? until;
  final int daysLeft;
}

/// The last day [calendar] covers without a gap from [today]'s year:
/// December 31 of the last of its years that follow on one another from
/// there; null when it does not cover [today]'s year.
BusinessDate? coveredUntil(HolidayCalendar calendar, BusinessDate today) {
  if (!calendar.years.contains(today.year)) return null;
  var year = today.year;
  while (calendar.years.contains(year + 1)) {
    year++;
  }
  return BusinessDate(year, 12, 31);
}

/// Whether [calendar] still covers more than [holidayTableLeadDays] past
/// [today]. [today] is given: the guard on CI passes the real day.
///
/// A release check, not app code: its only callers are the coverage
/// guard tests of each holiday table (D33), which fail on CI before a
/// table runs out. Keep it although nothing in lib/ calls it.
HolidayCoverage holidayCoverage(HolidayCalendar calendar, BusinessDate today) {
  final until = coveredUntil(calendar, today);
  if (until == null) return const CoverageEnding(null, 0);
  final left = today.daysUntil(until);
  return left > holidayTableLeadDays
      ? CoverageAhead(until)
      : CoverageEnding(until, left);
}
