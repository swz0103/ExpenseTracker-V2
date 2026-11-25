import 'package:core/foundation_values.dart';
import 'package:ledger_trade_costs/calc/settlement.dart';
import 'package:ledger_trade_costs/model/trade_values.dart';
import 'package:ledger_trade_costs/rules/taiwan_market_days.dart';
import 'package:test/test.dart';

void main() {
  group('settlementAmount', () {
    test('a buy pays the trade and the fee', () {
      // 100,000 + 85 fee = 100,085 paid out.
      expect(settlementAmount(TradeKind.buy, gross: 100000, fee: 85), -100085);
    });

    test('a sale receives the trade less fee and tax', () {
      // 100,000 - 85 fee - 300 tax = 99,615.
      expect(
        settlementAmount(TradeKind.sell, gross: 100000, fee: 85, tax: 300),
        99615,
      );
      // 1,000,000 - 855 fee - 3,000 tax = 996,145.
      expect(
        settlementAmount(TradeKind.sell, gross: 1000000, fee: 855, tax: 3000),
        996145,
      );
    });

    test('a cash dividend receives the gross less the premium', () {
      // 25,000 - 528 premium = 24,472.
      expect(
        settlementAmount(TradeKind.dividend, gross: 25000, tax: 528),
        24472,
      );
    });

    test('a capital reduction returns the gross, fee and tax aside', () {
      expect(
        settlementAmount(
          TradeKind.capitalReturn,
          gross: 40000,
          fee: 10,
          tax: 20,
        ),
        40000,
      );
    });

    test('nothing traded moves nothing', () {
      expect(settlementAmount(TradeKind.buy, gross: 0), 0);
      expect(settlementAmount(TradeKind.sell, gross: 0), 0);
    });
  });

  group('taiwanSettlementDate', () {
    BusinessDate d(int y, int m, int day) => BusinessDate(y, m, day);
    BusinessDayAnswer<BusinessDate> settles(BusinessDate traded) =>
        taiwanSettlementDate(traded, taiwanMarketDays);

    test('two exchange days after the trade', () {
      // Thu 2026-10-01: Fri 10-02 is day 1, Mon 10-05 day 2.
      expect(settles(d(2026, 10, 1)).value, d(2026, 10, 5));
      expect(settles(d(2026, 10, 1)), isA<Verified<BusinessDate>>());
      // Fri 2026-10-02: Mon 10-05 is day 1, Tue 10-06 day 2.
      expect(settles(d(2026, 10, 2)).value, d(2026, 10, 6));
    });

    test('a public holiday is skipped (decision D24)', () {
      // Wed 2026-10-07: Thu 10-08 is day 1, Fri 10-09 is 補假, then the
      // weekend, so Mon 10-12 is day 2.
      expect(settles(d(2026, 10, 7)).value, d(2026, 10, 12));
      // Thu 2026-10-08: Mon 10-12 is day 1 and Tue 10-13 day 2.
      expect(settles(d(2026, 10, 8)).value, d(2026, 10, 13));
      // Fri 2026-02-13: 02-16 to 02-20 are the Lunar New Year and its
      // 補假, so Mon 02-23 is day 1 and Tue 02-24 day 2.
      expect(settles(d(2026, 2, 13)).value, d(2026, 2, 24));
    });

    test('a make-up Saturday is not an exchange day', () {
      // Thu 2025-02-06: Fri 02-07 is day 1; Sat 02-08 is 補行上班 for
      // offices, but the exchange 「不交易亦不交割」, so Mon 02-10 is day 2.
      expect(settles(d(2025, 2, 6)).value, d(2025, 2, 10));
      // The office calendar alone would give the Saturday.
      expect(
        taiwanSettlementDate(d(2025, 2, 6), taiwanHolidays).value,
        d(2025, 2, 8),
      );
    });

    test('Labour Day closes the market though offices were open', () {
      // Tue 2025-04-29: Wed 04-30 is day 1, Thu 05-01 is closed, Fri
      // 05-02 day 2. (The office calendar alone gives Thu 05-01.)
      expect(settles(d(2025, 4, 29)).value, d(2025, 5, 2));
      expect(settles(d(2025, 4, 29)), isA<Verified<BusinessDate>>());
      expect(
        taiwanSettlementDate(d(2025, 4, 29), taiwanHolidays).value,
        d(2025, 5, 1),
      );
    });

    test('past the years on record only weekends are skipped, and said', () {
      // Wed 2028-01-05 + 2 weekdays = Fri 01-07; 2028 is in no table.
      final later = settles(d(2028, 1, 5));
      expect(later.value, d(2028, 1, 7));
      expect(later, isA<WeekendsOnly<BusinessDate>>());
      expect((later as WeekendsOnly).year, 2028);
      // Mon 2028-10-09: 10-10 (國慶日) is not known, so Wed 10-11.
      expect(settles(d(2028, 10, 9)).value, d(2028, 10, 11));
      // Thu 2027-12-30: Fri 12-31 is 補假 (known), Mon 2028-01-03 is day
      // 1 and Tue 01-04 day 2, counted into a year not on record.
      final across = settles(d(2027, 12, 30));
      expect(across.value, d(2028, 1, 4));
      expect(across, isA<WeekendsOnly<BusinessDate>>());
      // Before the tables as well: Wed 2024-10-09 + 2 = Fri 10-11 (10-10
      // was a holiday, not known here).
      final earlier = settles(d(2024, 10, 9));
      expect(earlier.value, d(2024, 10, 11));
      expect(earlier, isA<WeekendsOnly<BusinessDate>>());
    });
  });
}
