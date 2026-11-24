/// The guard that keeps the market closures table from running out (D33).
///
/// It reads the REAL date on purpose (`SystemClock`): run on CI, it starts
/// to fail 60 days (`holidayTableLeadDays`) before the last day the table
/// covers, so the next year's closures are added in time and settlement
/// never silently falls back to weekends only. When it fails, extend the
/// file it names. The guard's own logic is tested with fixed days in
/// core's coverage_test.dart.
library;

import 'package:core/time/time.dart';
import 'package:ledger_trade_costs/rules/taiwan_market_days.dart';
import 'package:test/test.dart';

void main() {
  test('the market closures table covers more than 60 days ahead', () {
    final coverage = holidayCoverage(
      HolidayCalendar.parse(taiwanMarketClosureTable),
      const SystemClock().today(),
    );
    expect(
      coverage,
      isA<CoverageAhead>(),
      reason:
          'The market closures table runs out (${switch (coverage) {
            CoverageEnding(:final until) => until ?? 'already',
            CoverageAhead(:final until) => until,
          }}): add the next year to '
          'packages/ledger/trade_costs/lib/rules/taiwan_market_days.dart '
          '(rows and the years: line), after the office table.',
    );
  });
}
