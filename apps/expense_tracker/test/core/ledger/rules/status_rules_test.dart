import 'package:expense_tracker/src/core/ledger/rules/advance_rules.dart';
import 'package:expense_tracker/src/core/ledger/rules/budget_rules.dart';
import 'package:expense_tracker/src/core/ledger/rules/recurring_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('budgetStatus', () {
    BudgetStatus of(int spent) =>
        budgetStatus(spent: spent, limit: 50000, warningPercent: 80);

    test('under the warning share is within, with what is left', () {
      // 50,000 - 39,999 = 10,001; 39,999 is under 80% (40,000).
      expect(of(39999), const BudgetWithin(10001));
    });

    test('from the warning share on it is near', () {
      // 80% of 50,000 = 40,000 exactly: 10,000 left.
      expect(of(40000), const BudgetNear(10000));
    });

    test('exactly at the limit is near, not over', () {
      expect(of(50000), const BudgetNear(0));
    });

    test('one unit over the limit is over by one', () {
      expect(of(50001), const BudgetOver(1));
    });

    test('over is decided on amounts, not a rounded percent', () {
      // 50,174 / 50,000 rounds to 100%, yet it is 174 over.
      expect(of(50174), const BudgetOver(174));
    });
  });

  group('recurringPeriodStatus', () {
    final today = DateTime.utc(2026, 11, 20);
    RecurringPeriodStatus of(
      DateTime day, {
      bool active = true,
      bool booked = false,
      bool skipped = false,
    }) => recurringPeriodStatus(
      active: active,
      booked: booked,
      skipped: skipped,
      day: day,
      today: today,
    );

    test('a day still to come is upcoming', () {
      expect(of(DateTime.utc(2026, 11, 21)), RecurringPeriodStatus.upcoming);
    });

    test('today and earlier unbooked days are due', () {
      expect(of(today), RecurringPeriodStatus.due);
      expect(of(DateTime.utc(2026, 11, 19)), RecurringPeriodStatus.due);
    });

    test('a booked day is booked, a let-go day is skipped', () {
      expect(of(today, booked: true), RecurringPeriodStatus.booked);
      expect(of(today, skipped: true), RecurringPeriodStatus.skipped);
    });

    test('a paused item is paused whatever its day', () {
      expect(
        of(DateTime.utc(2026, 11, 1), active: false),
        RecurringPeriodStatus.paused,
      );
    });
  });

  group('advanceStatus', () {
    test('nothing back is open', () {
      expect(advanceStatus(amount: 500, left: 500), AdvanceStatus.open);
    });

    test('some back is partly settled', () {
      // 500 lent, 499 still owed: 1 came back.
      expect(
        advanceStatus(amount: 500, left: 499),
        AdvanceStatus.partlySettled,
      );
    });

    test('all back is settled', () {
      expect(advanceStatus(amount: 500, left: 0), AdvanceStatus.settled);
    });
  });
}
