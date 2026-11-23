import 'package:core/foundation_values.dart' show taiwanHolidays;
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

  test('settlement skips only weekends unless a calendar is given', () {
    // Wed 2026-10-07 + 2 weekdays = Fri 10-09 (today's behaviour).
    expect(settlementDay(DateTime.utc(2026, 10, 7)), DateTime.utc(2026, 10, 9));
    // With the official calendar, Fri 10-09 (補假) and the weekend are
    // skipped: Thu 10-08 is day 1, Mon 10-12 day 2.
    expect(
      settlementDay(
        DateTime.utc(2026, 10, 7),
        calendar: taiwanHolidays.banking,
      ),
      DateTime.utc(2026, 10, 12),
    );
  });
}
