// Card statement cycles: which statement closed last, when its cycle
// began and when it is due, for closing days 28 to 31 around February
// (2026 is a common year, 2028 a leap year). Dates are counted by hand.
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'baseline_ledger.dart';

Account card(int closing, {int due = 15, Map<DateTime, DateTime>? closes}) =>
    Account(
      'card',
      '信用卡',
      AccountKind.card,
      0,
      closingDay: closing,
      dueDay: due,
      closes: closes ?? const {},
    );

void main() {
  group('closing day 31', () {
    final a = card(31);
    test('February 2026 closes on the 28th', () {
      expect(a.closingOn(day(2026, 3, 15)), day(2026, 2, 28));
      // Cycle: after Jan 31, so from Feb 1; due the 15th, Feb 15 is not
      // after the Feb 28 close, so Mar 15.
      expect(a.cycleEnding(day(2026, 2, 28)), (
        day(2026, 2, 1),
        day(2026, 3, 15),
      ));
    });
    test('February 2028 (leap) closes on the 29th', () {
      expect(a.closingOn(day(2028, 3, 15)), day(2028, 2, 29));
      expect(a.cycleEnding(day(2028, 2, 29)), (
        day(2028, 2, 1),
        day(2028, 3, 15),
      ));
      // The 28th is still before the close.
      expect(a.closingOn(day(2028, 2, 28)), day(2028, 1, 31));
    });
    test('a 31-day month closes on the 31st, a 30-day month on the 30th', () {
      expect(a.closingOn(day(2026, 3, 31)), day(2026, 3, 31));
      // Cycle after Feb 28 starts Mar 1; due Mar 15 is before the close,
      // so Apr 15.
      expect(a.cycleEnding(day(2026, 3, 31)), (
        day(2026, 3, 1),
        day(2026, 4, 15),
      ));
      expect(a.closingOn(day(2026, 4, 29)), day(2026, 3, 31));
      expect(a.closingOn(day(2026, 4, 30)), day(2026, 4, 30));
    });
  });

  group('closing day 30', () {
    final a = card(30);
    test('February 2026 closes on the 28th, its cycle from Jan 31', () {
      expect(a.closingOn(day(2026, 3, 15)), day(2026, 2, 28));
      // Previous close Jan 30, so the cycle starts Jan 31.
      expect(a.cycleEnding(day(2026, 2, 28)), (
        day(2026, 1, 31),
        day(2026, 3, 15),
      ));
    });
    test('February 2028 (leap) closes on the 29th', () {
      expect(a.closingOn(day(2028, 3, 15)), day(2028, 2, 29));
      expect(a.cycleEnding(day(2028, 2, 29)), (
        day(2028, 1, 31),
        day(2028, 3, 15),
      ));
    });
    test('March closes on the 30th, its cycle from Mar 1', () {
      expect(a.closingOn(day(2026, 3, 31)), day(2026, 3, 30));
      expect(a.cycleEnding(day(2026, 3, 30)).$1, day(2026, 3, 1));
    });
  });

  group('closing day 29', () {
    final a = card(29);
    test('February 2026 closes on the 28th, its cycle from Jan 30', () {
      expect(a.closingOn(day(2026, 3, 10)), day(2026, 2, 28));
      // Previous close Jan 29, so the cycle starts Jan 30.
      expect(a.cycleEnding(day(2026, 2, 28)).$1, day(2026, 1, 30));
      expect(a.closingOn(day(2026, 2, 27)), day(2026, 1, 29));
    });
    test('February 2028 (leap) closes on the 29th', () {
      expect(a.closingOn(day(2028, 3, 10)), day(2028, 2, 29));
      expect(a.cycleEnding(day(2028, 2, 29)).$1, day(2028, 1, 30));
      expect(a.closingOn(day(2028, 2, 28)), day(2028, 1, 29));
    });
  });

  group('closing day 28', () {
    final a = card(28);
    test('closes on the 28th in every February, leap or not', () {
      expect(a.closingOn(day(2026, 3, 1)), day(2026, 2, 28));
      expect(a.closingOn(day(2028, 3, 1)), day(2028, 2, 28));
      // Leap day 29 is after the close, still the same statement.
      expect(a.closingOn(day(2028, 2, 29)), day(2028, 2, 28));
    });
    test('the cycle runs from Jan 29 and is due Mar 15', () {
      expect(a.cycleEnding(day(2026, 2, 28)), (
        day(2026, 1, 29),
        day(2026, 3, 15),
      ));
    });
  });

  group('due days', () {
    test('a due day before the closing day falls in the next month', () {
      // Closing 25, due 10: closes Jan 25, due Feb 10; cycle from Dec 26.
      expect(card(25, due: 10).cycleEnding(day(2026, 1, 25)), (
        day(2025, 12, 26),
        day(2026, 2, 10),
      ));
    });
    test('a due day after the closing day is in the same month', () {
      // Closing 5, due 20: closes Jan 5, due Jan 20; cycle from Dec 6.
      expect(card(5, due: 20).cycleEnding(day(2026, 1, 5)), (
        day(2025, 12, 6),
        day(2026, 1, 20),
      ));
    });
    test('a due day 31 in February is the last day of it', () {
      // Closing 20, due 31: Feb 20 close, due Feb 28 (2026).
      expect(
        card(20, due: 31).cycleEnding(day(2026, 2, 20)).$2,
        day(2026, 2, 28),
      );
    });
    test('closing day 1: the cycle is the whole previous month', () {
      expect(card(1).closingOn(day(2026, 3, 1)), day(2026, 3, 1));
      // Previous close Feb 1, so Feb 2 to Mar 1; due Mar 15.
      expect(card(1).cycleEnding(day(2026, 3, 1)), (
        day(2026, 2, 2),
        day(2026, 3, 15),
      ));
    });
  });

  group('a statement the issuer closed early', () {
    test('a moved close is the close, and its due day stays scheduled', () {
      // Scheduled Mar 20, closed on Mar 19; due Apr 5 as scheduled.
      final a = card(20, due: 5, closes: {day(2026, 3, 20): day(2026, 3, 19)});
      expect(a.closingOn(day(2026, 3, 19)), day(2026, 3, 19));
      expect(a.closingOn(day(2026, 3, 18)), day(2026, 2, 20));
      expect(a.cycleEnding(day(2026, 3, 19)), (
        day(2026, 2, 21),
        day(2026, 4, 5),
      ));
    });
  });

  group('the statement the ledger shows', () {
    // A card closing on the 31st, due the 15th, with these entries:
    // 1,000 on Feb 10, 200 on Feb 28 (the closing day), 500 on Mar 1.
    Ledger book(DateTime today, {List<Entry> more = const []}) => ledgerOf(
      today: today,
      accounts: [
        card(31),
        const Account('bank', '銀行', AccountKind.bank, 100000),
      ],
      entries: [
        entryOf('a', day(2026, 2, 10), EntryType.expense, 1000, 'card'),
        entryOf('b', day(2026, 2, 28), EntryType.expense, 200, 'card'),
        entryOf('c', day(2026, 3, 1), EntryType.expense, 500, 'card'),
        ...more,
      ],
    );

    test('on the closing day the statement is still open', () {
      // Today Feb 28: closed by Feb 27, so the last statement is Jan's.
      final ledger = book(day(2026, 2, 28));
      final s = ledger.statementService.statement(ledger.account('card'));
      expect(s, (day(2026, 1, 1), day(2026, 1, 31), day(2026, 2, 15)));
    });
    test('the day after, February is closed', () {
      final ledger = book(day(2026, 3, 1));
      final s = ledger.statementService.statement(ledger.account('card'));
      expect(s, (day(2026, 2, 1), day(2026, 2, 28), day(2026, 3, 15)));
    });
    test('what is due is what the statement closed owing', () {
      final ledger = book(day(2026, 3, 5));
      // 1000 + 200 on or before Feb 28; the 500 of Mar 1 is the next one.
      expect(
        ledger.statementService.statementDue(ledger.account('card')),
        1200,
      );
      final open = ledger.statementService.unbilled(ledger.account('card'));
      expect([for (final e in open) e.id], ['c']);
    });
    test('a payment before the close lowers the statement', () {
      final ledger = book(
        day(2026, 3, 5),
        more: [
          entryOf(
            'p',
            day(2026, 2, 20),
            EntryType.transfer,
            300,
            'bank',
            to: 'card',
          ),
        ],
      );
      // Balance at Feb 28 = -1000 - 200 + 300 = -900.
      expect(ledger.statementService.statementDue(ledger.account('card')), 900);
    });
    test('a payment after the close is taken off what is due', () {
      final ledger = book(
        day(2026, 3, 5),
        more: [
          entryOf(
            'p',
            day(2026, 3, 3),
            EntryType.transfer,
            400,
            'bank',
            to: 'card',
          ),
        ],
      );
      // Owed at close 1200, paid since 400: 800.
      expect(ledger.statementService.statementDue(ledger.account('card')), 800);
    });
    test('overpaying leaves nothing due, not a negative amount', () {
      final ledger = book(
        day(2026, 3, 5),
        more: [
          entryOf(
            'p',
            day(2026, 3, 3),
            EntryType.transfer,
            5000,
            'bank',
            to: 'card',
          ),
        ],
      );
      expect(ledger.statementService.statementDue(ledger.account('card')), 0);
    });
  });
}
