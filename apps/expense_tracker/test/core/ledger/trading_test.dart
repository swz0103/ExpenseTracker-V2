import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/trading.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bond ETFs are sold without the securities tax while exempt', () {
    final day = DateTime.utc(2026, 10, 27);
    expect(saleTax('2330', 100000, 100, day), 300);
    expect(saleTax('0050', 100000, 1000, day), 100);
    expect(saleTax('00679B', 100000, 3000, day), 0);
  });

  test('a dividend of NT\$20,000 or more pays the 2.11% premium', () {
    final day = DateTime.utc(2026, 10, 2);
    expect(dividendPremium(19999, day), 0);
    expect(dividendPremium(20000, day), 422);
    expect(dividendPremium(30000, day), 633);
  });

  test('settlement is T+2 on market days, holidays skipped (D24)', () {
    BusinessDate d(int y, int m, int day) => BusinessDate(y, m, day);
    // Wed 2026-10-07: Thu 10-08 is day 1, Fri 10-09 (補假) and the
    // weekend are skipped, Mon 10-12 is day 2.
    final october = settlementDay(DateTime.utc(2026, 10, 7));
    expect(october.value, d(2026, 10, 12));
    expect(october, isA<Verified<BusinessDate>>());
    // Tue 2025-04-29: Wed 04-30 is day 1, Thu 05-01 (勞動節) is a market
    // day off, Fri 05-02 day 2.
    expect(settlementDay(DateTime.utc(2025, 4, 29)).value, d(2025, 5, 2));
    // The time of day does not matter.
    expect(settlementDay(DateTime(2026, 10, 7, 23, 59)).value, d(2026, 10, 12));
  });

  test('past the years on record settlement skips weekends only', () {
    // Wed 2028-01-05 + 2 weekdays = Fri 01-07; 2028 is in no table.
    final later = settlementDay(DateTime.utc(2028, 1, 5));
    expect(later.value, BusinessDate(2028, 1, 7));
    expect(later, isA<WeekendsOnly<BusinessDate>>());
  });
}
