// Broker fee, transaction tax, dividend premium and settlement day: every
// expected figure is worked out by hand in the comment beside it.
import 'package:core/foundation_values.dart';
import 'package:domain/investments.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/trading.dart';
import 'package:flutter_test/flutter_test.dart';

import 'baseline_ledger.dart';

Money ntd(int v) => Money(Currency.of('TWD'), BigInt.from(v));

void main() {
  group('broker fee at the app 60% discount (0.1425% x 0.6, rounded down)', () {
    test('100,000 for a board lot costs 85', () {
      // 100000 x 0.001425 = 142.5; x 0.6 = 85.5; rounded down = 85.
      expect(brokerFee(100000, 1000), 85);
    });
    test('50,000 costs 42', () {
      // 50000 x 0.001425 = 71.25; x 0.6 = 42.75 -> 42.
      expect(brokerFee(50000, 1000), 42);
    });
    test('1,000,000 costs 855 exactly', () {
      // 1000000 x 0.001425 = 1425; x 0.6 = 855.
      expect(brokerFee(1000000, 1000), 855);
    });
    test('a board lot pays at least 20', () {
      // 10000 x 0.001425 x 0.6 = 8.55 -> 8, below the 20 minimum.
      expect(brokerFee(10000, 1000), 20);
      // 20000 x 0.001425 x 0.6 = 17.1 -> 17, below 20.
      expect(brokerFee(20000, 1000), 20);
      // 23392 x 0.000855 = 19.99 -> 19, below 20.
      expect(brokerFee(23392, 1000), 20);
      // 33333 x 0.000855 = 28.4997 -> 28, above 20.
      expect(brokerFee(33333, 1000), 28);
    });
    test('an odd lot (under 1000 shares) pays at least 1, not 20', () {
      // 10000 x 0.000855 = 8.55 -> 8, above the odd-lot minimum.
      expect(brokerFee(10000, 100), 8);
      // 5 shares for 500: 500 x 0.000855 = 0.4275 -> 0, raised to 1.
      expect(brokerFee(500, 5), 1);
      // 999 shares is still an odd lot: 1000 x 0.000855 = 0.855 -> 0 -> 1.
      expect(brokerFee(1000, 999), 1);
    });
    test('nothing to trade, nothing to charge', () {
      expect(brokerFee(0, 1000), 0);
      expect(brokerFee(100000, 0), 0);
      expect(brokerFee(-5, 10), 0);
    });
  });

  group('broker fee in the domain package at other discounts', () {
    final lot = ShareQuantity.parse('1000');
    int fee(int bp, int gross) =>
        TaiwanTradeCharges(discountBasisPoints: bp)
            .fee(ntd(gross), lot)
            .minorUnits
            .toInt();
    test('no discount, 2.8折 and 6折 on 100,000', () {
      // 100000 x 0.001425 = 142.5 -> 142.
      expect(fee(10000, 100000), 142);
      // 142.5 x 0.28 = 39.9 -> 39.
      expect(fee(2800, 100000), 39);
      // 142.5 x 0.6 = 85.5 -> 85.
      expect(fee(6000, 100000), 85);
    });
    test('a discount outside 0.01%..100% is refused', () {
      expect(
        () => TaiwanTradeCharges(discountBasisPoints: 0),
        throwsA(isA<InvestmentException>()),
      );
      expect(
        () => TaiwanTradeCharges(discountBasisPoints: 10001),
        throwsA(isA<InvestmentException>()),
      );
    });
    test('fractional shares are refused for Taiwan stocks', () {
      expect(
        () => TaiwanTradeCharges().fee(ntd(100), ShareQuantity.parse('1.5')),
        throwsA(isA<InvestmentException>()),
      );
    });
  });

  group('securities transaction tax on a sale', () {
    final oct = day(2026, 10, 5);
    test('a stock pays 0.3%, rounded down', () {
      // 100000 x 0.003 = 300.
      expect(saleTax('2330', 100000, 1000, oct), 300);
      // 99999 x 0.003 = 299.997 -> 299.
      expect(saleTax('2330', 99999, 1000, oct), 299);
    });
    test('an ETF pays 0.1%', () {
      // 100000 x 0.001 = 100.
      expect(saleTax('0050', 100000, 1000, oct), 100);
      // 99999 x 0.001 = 99.999 -> 99.
      expect(saleTax('00713', 99999, 1000, oct), 99);
    });
    test('a bond ETF is exempt through 2026 and pays 0.1% from 2027', () {
      expect(saleTax('00720B', 100000, 1000, oct), 0);
      expect(saleTax('00720B', 100000, 1000, day(2026, 12, 31)), 0);
      // 100000 x 0.001 = 100 once the exemption ends.
      expect(saleTax('00720B', 100000, 1000, day(2027, 1, 4)), 100);
    });
    test('a day trade of a stock pays 0.15%', () {
      final c = TaiwanTradeCharges(discountBasisPoints: 6000);
      final tax = c.sellTax(
        ntd(100000),
        ShareQuantity.parse('1000'),
        kind: InstrumentKind.stock,
        tradedOn: BusinessDate(2026, 10, 5),
        dayTrade: true,
      );
      // 100000 x 0.0015 = 150.
      expect(tax.minorUnits, BigInt.from(150));
    });
    test('nothing sold pays no tax', () {
      expect(saleTax('2330', 0, 1000, oct), 0);
      expect(saleTax('2330', 100000, 0, oct), 0);
    });
    test('before the rates on record the app suggests nothing', () {
      expect(saleTax('2330', 100000, 1000, day(2015, 6, 1)), 0);
    });
  });

  group('a sale as the ledger books it', () {
    test('selling 100,000 of shares nets 99,615', () {
      final ledger = ledgerOf(
        today: day(2026, 10, 5),
        accounts: const [Account('bank', '銀行', AccountKind.bank, 200000)],
      );
      ledger.entryCommands
        ..add(
          entryOf(
            'b',
            day(2026, 10, 1),
            EntryType.buy,
            100000,
            'bank',
            holding: '2330',
            shares: 1000,
            fee: 85,
          ),
        )
        ..add(
          entryOf(
            's',
            day(2026, 10, 5),
            EntryType.sell,
            100000,
            'bank',
            holding: '2330',
            shares: 1000,
            fee: 85,
            tax: 300,
          ),
        );
      // Opening 200000; buy -(100000+85); sell +(100000-85-300) = 99615.
      // 200000 - 100085 + 99615 = 199530.
      expect(ledger.balanceService.balance('bank'), 199530);
      // The sale alone: 100000 - 85 - 300 = 99615.
      expect(
        ledger.balanceService.effect(ledger.entries.all.last, 'bank'),
        99615,
      );
    });
  });

  group('supplementary health premium on a cash dividend (2.11%)', () {
    final paid = day(2026, 8, 15);
    test('25,000 is charged 528 and nets 24,472', () {
      // 25000 x 0.0211 = 527.5, rounded half up = 528.
      expect(dividendPremium(25000, paid), 528);
      // 25000 - 528 = 24472.
      final e = entryOf(
        'd',
        paid,
        EntryType.dividend,
        25000,
        'bank',
        holding: '2330',
        tax: 528,
      );
      expect(e.dividendNet, 24472);
      expect(e.earning, 24472);
    });
    test('below 20,000 nothing is withheld, at 20,000 it starts', () {
      expect(dividendPremium(19999, paid), 0);
      // 20000 x 0.0211 = 422.
      expect(dividendPremium(20000, paid), 422);
      // 30000 x 0.0211 = 633.
      expect(dividendPremium(30000, paid), 633);
    });
    test('the base is capped at 10,000,000', () {
      // 12,000,000 counts as 10,000,000 x 0.0211 = 211,000.
      expect(dividendPremium(12000000, paid), 211000);
    });
    test('payments of 2020 use the 1.91% rate, 2021 on 2.11%', () {
      // 25000 x 0.0191 = 477.5 -> 478.
      expect(dividendPremium(25000, day(2020, 12, 31)), 478);
      expect(dividendPremium(25000, day(2021, 1, 1)), 528);
    });
    test('the ledger credits the net and counts it as dividend income', () {
      final ledger = ledgerOf(today: paid);
      ledger.entryCommands
        ..add(
          entryOf(
            'b',
            day(2026, 1, 5),
            EntryType.buy,
            100000,
            'bank',
            holding: '2330',
            shares: 1000,
          ),
        )
        ..add(
          entryOf(
            'd',
            paid,
            EntryType.dividend,
            25000,
            'bank',
            holding: '2330',
            tax: 528,
          ),
        );
      // Opening 0 - 100000 (buy) + 24472 (dividend net) = -75528.
      expect(ledger.balanceService.balance('bank'), -75528);
      expect(ledger.reportService.income(2026, 8), 24472);
      expect(ledger.reportService.dividends(2026, 8), 24472);
      expect(ledger.holding('2330')!.dividends, 24472);
    });
  });

  group('settlement is two open days after the trade (T+2)', () {
    test('a Wednesday trade settles on Friday', () {
      // 2026-10-07 is a Wednesday; +2 weekdays = Friday 2026-10-09.
      expect(settlementDay(day(2026, 10, 7)), day(2026, 10, 9));
    });
    test('a Friday trade settles on Tuesday', () {
      // Fri 2026-10-02: Mon 10-05 is day 1, Tue 10-06 day 2.
      expect(settlementDay(day(2026, 10, 2)), day(2026, 10, 6));
    });
    test('a Thursday trade settles on Monday', () {
      // Thu 2026-10-01: Fri 10-02 day 1, Mon 10-05 day 2.
      expect(settlementDay(day(2026, 10, 1)), day(2026, 10, 5));
    });
  });
}
