import 'package:core/foundation_values.dart';
import 'package:ledger_trade_costs/rules/taiwan_market_days.dart';
import 'package:test/test.dart';

void main() {
  BusinessDate d(int y, int m, int day) => BusinessDate(y, m, day);

  test('the market table lists Labour Day for the years on record', () {
    final table = HolidayCalendar.parse(taiwanMarketClosureTable);
    expect(table.years, {2025, 2026, 2027});
    expect(table.holidays, {
      d(2025, 5, 1): '勞動節',
      d(2026, 5, 1): '勞動節',
      d(2027, 5, 1): '勞動節',
    });
    expect(table.workdays, isEmpty);
  });

  test('the market is closed on office days off and on Labour Day', () {
    expect(taiwanMarketDays.years, {2025, 2026, 2027});
    // Thu 2025-05-01: an office day, a market day off.
    expect(taiwanHolidays.isBusinessDay(d(2025, 5, 1)).value, isTrue);
    expect(taiwanMarketDays.isBusinessDay(d(2025, 5, 1)).value, isFalse);
    // Fri 2026-10-09 補假: off for both.
    expect(taiwanMarketDays.isBusinessDay(d(2026, 10, 9)).value, isFalse);
    // Sat 2025-02-08 補行上班: offices open, the exchange neither trades
    // nor settles.
    expect(taiwanHolidays.isBusinessDay(d(2025, 2, 8)).value, isTrue);
    expect(taiwanMarketDays.isBusinessDay(d(2025, 2, 8)).value, isFalse);
    expect(taiwanMarketDays.workdays, isEmpty);
  });

  test('trades settle T+2', () {
    expect(taiwanSettlementDays, 2);
  });
}
