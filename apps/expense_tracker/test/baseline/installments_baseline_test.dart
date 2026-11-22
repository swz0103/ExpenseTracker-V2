// Instalment purchases: the remainder goes in the first period, and each
// period reaches the card balance when its statement closes. Figures are
// worked out by hand beside each assertion.
import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'baseline_ledger.dart';

void main() {
  group('how a purchase is split (equal parts rounded down, rest first)', () {
    test('10,001 over 3 periods is 3,335 then 3,333 and 3,333', () {
      // 10001 ~/ 3 = 3333; first = 10001 - 3333 x 2 = 3335.
      expect(installmentAmounts(10001, 3), [3335, 3333, 3333]);
    });
    test('100 over 3 periods is 34, 33, 33', () {
      // 100 ~/ 3 = 33; first = 100 - 66 = 34.
      expect(installmentAmounts(100, 3), [34, 33, 33]);
    });
    test('100 over 7 periods is 16 then six of 14', () {
      // 100 ~/ 7 = 14; first = 100 - 14 x 6 = 16.
      expect(installmentAmounts(100, 7), [16, 14, 14, 14, 14, 14, 14]);
    });
    test('1,000,000 over 12 periods starts with 83,337', () {
      // 1000000 ~/ 12 = 83333; first = 1000000 - 83333 x 11 = 83337.
      final parts = installmentAmounts(1000000, 12);
      expect(parts.first, 83337);
      expect(parts.skip(1).toSet(), {83333});
    });
    test('an exact division has equal parts', () {
      // 12000 / 3 = 4000 each.
      expect(installmentAmounts(12000, 3), [4000, 4000, 4000]);
    });
    test('an amount smaller than the periods lands in the first one', () {
      // 5 ~/ 6 = 0; first = 5 - 0 = 5.
      expect(installmentAmounts(5, 6), [5, 0, 0, 0, 0, 0]);
    });
    test('10 over 4 periods is 4, 2, 2, 2', () {
      // 10 ~/ 4 = 2; first = 10 - 6 = 4.
      expect(installmentAmounts(10, 4), [4, 2, 2, 2]);
    });
    test('one period, or none given, is the whole amount at once', () {
      expect(installmentAmounts(777, 1), [777]);
      expect(installmentAmounts(777, 0), [777]);
    });
    test('the parts always add back to the purchase', () {
      // Sums checked by hand: 3335+3333+3333 = 10001; 16+14x6 = 100.
      expect(installmentAmounts(10001, 3).fold(0, (a, b) => a + b), 10001);
      expect(installmentAmounts(100, 7).fold(0, (a, b) => a + b), 100);
    });
    test('the domain package refuses a nonsense split', () {
      expect(
        () => installmentShares(100, 0),
        throwsA(isA<CreditCardException>()),
      );
      expect(
        () => installmentShares(-1, 3),
        throwsA(isA<CreditCardException>()),
      );
    });
  });

  group('when each period reaches the card balance (closing day 20)', () {
    // A card closing on the 20th, due on the 5th, owing nothing.
    const card = Account(
      'card',
      '信用卡',
      AccountKind.card,
      0,
      closingDay: 20,
      dueDay: 5,
    );

    Ledger bought(DateTime on, int amount, int count) => ledgerOf(
      today: day(2027, 1, 31),
      accounts: const [card],
      entries: [
        entryOf(
          'p',
          on,
          EntryType.expense,
          amount,
          'card',
          category: '購物',
          installments: count,
        ),
      ],
    );

    test(
      '10,001 in 3 periods bought on Oct 4 bills on Oct 20, Nov 20, Dec 20',
      () {
        final ledger = bought(day(2026, 10, 4), 10001, 3);
        int at(int m, int d) =>
            ledger.balanceService.balance('card', until: day(2026, m, d));
        // Before the first close nothing is billed.
        expect(at(10, 19), 0);
        // Oct 20 closes the first statement: -3335.
        expect(at(10, 20), -3335);
        expect(at(11, 19), -3335);
        // Nov 20: -3335 - 3333 = -6668.
        expect(at(11, 20), -6668);
        // Dec 20: -6668 - 3333 = -10001, the whole purchase.
        expect(at(12, 20), -10001);
        expect(at(12, 31), -10001);
      },
    );

    test('a purchase on the closing day itself falls in that statement', () {
      final ledger = bought(day(2026, 10, 20), 10001, 3);
      // First close Oct 20: -3335 already on Oct 20.
      expect(
        ledger.balanceService.balance('card', until: day(2026, 10, 20)),
        -3335,
      );
    });

    test('a purchase the day after the close starts a month later', () {
      final ledger = bought(day(2026, 10, 21), 10001, 3);
      int at(int m, int d) =>
          ledger.balanceService.balance('card', until: day(2026, m, d));
      expect(at(10, 31), 0);
      expect(at(11, 19), 0);
      // First close is Nov 20.
      expect(at(11, 20), -3335);
      // Dec 20: -3335 - 3333 = -6668.
      expect(at(12, 20), -6668);
      // Jan 20 2027: -6668 - 3333 = -10001.
      expect(
        ledger.balanceService.balance('card', until: day(2027, 1, 20)),
        -10001,
      );
    });

    test('billed periods are counted by the closes passed', () {
      final ledger = bought(day(2026, 10, 4), 10001, 3);
      final e = ledger.entries.all.single;
      final c = ledger.account('card');
      // Before Oct 20: none; on Oct 20: 1; on Nov 20: 2; Dec 20: 3.
      expect(c.billedPeriods(e, day(2026, 10, 19)), 0);
      expect(c.billedPeriods(e, day(2026, 10, 20)), 1);
      expect(c.billedPeriods(e, day(2026, 11, 20)), 2);
      expect(c.billedPeriods(e, day(2026, 12, 20)), 3);
      expect(c.billedPeriods(e, day(2027, 6, 1)), 3);
      // billed(): 3335, then 3335+3333 = 6668, then 10001.
      expect(c.billed(e, day(2026, 10, 20)), 3335);
      expect(c.billed(e, day(2026, 11, 20)), 6668);
      expect(c.billed(e, day(2026, 12, 20)), 10001);
    });

    test('billing steps list each close and its share', () {
      final ledger = bought(day(2026, 10, 4), 10001, 3);
      final steps = ledger
          .account('card')
          .billingSteps(ledger.entries.all.single);
      expect(steps, [
        (day(2026, 10, 20), 3335),
        (day(2026, 11, 20), 3333),
        (day(2026, 12, 20), 3333),
      ]);
    });

    test('closes keep going across the new year', () {
      final ledger = bought(day(2026, 11, 4), 100, 4);
      final steps = ledger
          .account('card')
          .billingSteps(ledger.entries.all.single);
      // 100 ~/ 4 = 25 each, no remainder.
      expect(steps, [
        (day(2026, 11, 20), 25),
        (day(2026, 12, 20), 25),
        (day(2027, 1, 20), 25),
        (day(2027, 2, 20), 25),
      ]);
    });

    test('a purchase in one payment bills at once', () {
      final ledger = bought(day(2026, 10, 4), 500, 0);
      // No instalments: -500 on the purchase day.
      expect(
        ledger.balanceService.balance('card', until: day(2026, 10, 4)),
        -500,
      );
    });
  });

  group('instalment closes in short months', () {
    test('closing day 31 closes on the last day of February', () {
      final closes = installmentCloses(BusinessDate(2026, 1, 31), 31, 3);
      expect(closes.map((c) => (c.year, c.month, c.day)), [
        (2026, 1, 31),
        (2026, 2, 28),
        (2026, 3, 31),
      ]);
    });
    test('closing day 30 in a leap February closes on the 29th', () {
      final closes = installmentCloses(BusinessDate(2028, 1, 30), 30, 3);
      expect(closes.map((c) => (c.year, c.month, c.day)), [
        (2028, 1, 30),
        (2028, 2, 29),
        (2028, 3, 30),
      ]);
    });
  });
}
