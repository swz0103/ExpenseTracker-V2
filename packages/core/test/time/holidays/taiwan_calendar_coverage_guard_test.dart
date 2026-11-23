/// The guard that keeps the office holiday table from running out (D33).
///
/// It reads the REAL date on purpose (`SystemClock`): run on CI, it starts
/// to fail 60 days (`holidayTableLeadDays`) before the last day the table
/// covers, so the next year's rows are added in time and business days
/// never silently fall back to weekends only. When it fails, extend the
/// file it names. The guard's own logic is tested with fixed days in
/// coverage_test.dart.
library;

import 'package:core/time/time.dart';
import 'package:test/test.dart';

void main() {
  test('the office holiday table covers more than 60 days ahead', () {
    final coverage = holidayCoverage(
      taiwanHolidays,
      const SystemClock().today(),
    );
    expect(
      coverage,
      isA<CoverageAhead>(),
      reason:
          'The office holiday table runs out (${switch (coverage) {
            CoverageEnding(:final until) => until ?? 'already',
            CoverageAhead(:final until) => until,
          }}): add the next year to '
          'packages/core/lib/time/holidays/taiwan_calendar_data.dart '
          '(rows and the years: line).',
    );
  });
}
