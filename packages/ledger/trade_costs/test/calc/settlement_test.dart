import 'package:core/foundation_values.dart';
import 'package:ledger_trade_costs/calc/settlement.dart';
import 'package:ledger_trade_costs/model/trade_values.dart';
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
    test('two open days after the trade', () {
      // Wed 2026-10-07 + 2 weekdays = Fri 2026-10-09.
      expect(
        taiwanSettlementDate(BusinessDate(2026, 10, 7), BankingCalendar()),
        BusinessDate(2026, 10, 9),
      );
    });

    test('a holiday of the calendar is skipped', () {
      // Thu 2026-10-08: Fri 10-09 is a holiday, so Mon 10-12 is day 1 and
      // Tue 10-13 day 2.
      final calendar = BankingCalendar(holidays: {BusinessDate(2026, 10, 9)});
      expect(
        taiwanSettlementDate(BusinessDate(2026, 10, 8), calendar),
        BusinessDate(2026, 10, 13),
      );
    });
  });
}
