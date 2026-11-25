import 'package:core/time/time.dart';
import 'package:test/test.dart';

/// A calendar covering [years], with no rows.
HolidayCalendar _covering(Set<int> years) =>
    HolidayCalendar(years: years, holidays: const {}, workdays: const {});

void main() {
  final table = _covering({2025, 2026, 2027});

  test('the lead is 60 days, one number for every table', () {
    expect(holidayTableLeadDays, 60);
  });

  test('a table covers to December 31 of its last year in a row', () {
    expect(
      coveredUntil(table, BusinessDate(2026, 11, 23)),
      BusinessDate(2027, 12, 31),
    );
    // A gap ends the run: 2029 does not follow 2027.
    expect(
      coveredUntil(_covering({2026, 2027, 2029}), BusinessDate(2026, 3, 1)),
      BusinessDate(2027, 12, 31),
    );
    expect(coveredUntil(table, BusinessDate(2028, 1, 1)), isNull);
  });

  test('more than 60 days left is ahead', () {
    // 2026-11-23 to 2027-12-31 is 403 days.
    expect(
      holidayCoverage(table, BusinessDate(2026, 11, 23)),
      isA<CoverageAhead>().having(
        (c) => c.until,
        'until',
        BusinessDate(2027, 12, 31),
      ),
    );
    // 2027-10-31 to 2027-12-31 is 61 days: still ahead.
    expect(
      holidayCoverage(table, BusinessDate(2027, 10, 31)),
      isA<CoverageAhead>(),
    );
  });

  test('60 days or fewer left is ending, with the days left', () {
    // 2027-11-01 to 2027-12-31 is 60 days.
    expect(
      holidayCoverage(table, BusinessDate(2027, 11, 1)),
      isA<CoverageEnding>().having((c) => c.daysLeft, 'daysLeft', 60),
    );
    expect(
      holidayCoverage(table, BusinessDate(2027, 12, 31)),
      isA<CoverageEnding>().having((c) => c.daysLeft, 'daysLeft', 0),
    );
    // A year not covered at all has run out.
    expect(
      holidayCoverage(table, BusinessDate(2028, 1, 5)),
      isA<CoverageEnding>()
          .having((c) => c.until, 'until', isNull)
          .having((c) => c.daysLeft, 'daysLeft', 0),
    );
  });

  test('the guard reads its day from a clock', () {
    final clock = FixedClock(UtcInstant(DateTime.utc(2027, 11, 15, 12)));
    // 2027-11-15 to 2027-12-31 is 46 days.
    expect(
      holidayCoverage(table, clock.today()),
      isA<CoverageEnding>().having((c) => c.daysLeft, 'daysLeft', 46),
    );
  });
}
