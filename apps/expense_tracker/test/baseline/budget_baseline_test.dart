// Budgets: what counts against a limit, the month-end forecast, and the
// one-month carry-over. Figures are counted by hand beside each assertion.
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'baseline_ledger.dart';

Entry spend(
  String id,
  DateTime on,
  int amount, {
  String category = '飲食',
  List<String> tags = const [],
  List<(String, int)> parts = const [],
  String account = 'bank',
  int? home,
}) => entryOf(
  id,
  on,
  EntryType.expense,
  amount,
  account,
  category: category,
  tags: tags,
  parts: parts,
  home: home,
);

Ledger book(DateTime today, List<Entry> entries) => ledgerOf(
  today: today,
  accounts: const [
    Account('bank', '銀行', AccountKind.bank, 0),
    Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
  ],
  categories: [
    Category('飲食', 'food', 0xFF5C9A83),
    Category('居家', 'home', 0xFF5B8DB0),
  ],
  entries: entries,
);

void main() {
  const food = Budget('飲食', 10000);

  group('what counts against a budget', () {
    test('a category budget counts only its own category in the month', () {
      final ledger = book(day(2026, 11, 15), [
        spend('a', day(2026, 11, 3), 6000),
        spend('b', day(2026, 11, 10), 1500),
        spend('c', day(2026, 11, 11), 999, category: '居家'),
        spend('d', day(2026, 10, 31), 700),
        spend('e', day(2026, 12, 1), 800),
      ]);
      // 6000 + 1500 = 7500; the other category and months are not counted.
      expect(ledger.budgetService.spentAgainst(food, 2026, 11), 7500);
      expect(ledger.budgetService.spentAgainst(food, 2026, 10), 700);
    });

    test('a refund takes its amount off the spending', () {
      final ledger = book(day(2026, 11, 15), [
        spend('a', day(2026, 11, 3), 6000),
        entryOf(
          'r',
          day(2026, 11, 5),
          EntryType.income,
          500,
          'bank',
          category: '飲食',
          refundOf: 'a',
        ),
      ]);
      // 6000 - 500 = 5500.
      expect(ledger.budgetService.spentAgainst(food, 2026, 11), 5500);
      expect(ledger.reportService.expense(2026, 11), 5500);
      // A refund is not income.
      expect(ledger.reportService.income(2026, 11), 0);
    });

    test('the total budget counts all spending', () {
      final ledger = book(day(2026, 11, 15), [
        spend('a', day(2026, 11, 3), 6000),
        spend('c', day(2026, 11, 11), 999, category: '居家'),
      ]);
      // 6000 + 999 = 6999.
      expect(
        ledger.budgetService.spentAgainst(
          const Budget(allSpending, 20000),
          2026,
          11,
        ),
        6999,
      );
    });

    test('a split counts each part under its own category', () {
      final ledger = book(day(2026, 11, 15), [
        spend(
          'a',
          day(2026, 11, 3),
          300,
          parts: const [('飲食', 200), ('居家', 100)],
        ),
      ]);
      // 200 of the 300 is food.
      expect(ledger.budgetService.spentAgainst(food, 2026, 11), 200);
      expect(
        ledger.budgetService.spentAgainst(const Budget('居家', 500), 2026, 11),
        100,
      );
      expect(ledger.reportService.expense(2026, 11), 300);
    });

    test('a tag budget counts spending carrying the tag', () {
      final ledger = book(day(2026, 11, 15), [
        spend('a', day(2026, 11, 3), 2000, tags: const ['旅遊']),
        spend('b', day(2026, 11, 4), 300, tags: const ['旅遊', '家用']),
        spend('c', day(2026, 11, 5), 50, tags: const ['家用']),
      ]);
      // 2000 + 300 = 2300.
      expect(
        ledger.budgetService.spentAgainst(const Budget('#旅遊', 5000), 2026, 11),
        2300,
      );
      expect(ledger.budgetService.spentOnTag('家用', 2026, 11), 350);
    });

    test('a foreign-currency purchase counts at its NT\$ amount', () {
      final ledger = book(day(2026, 11, 15), [
        // US$12.50 is 1250 cents; worth NT$400 that day.
        spend('u', day(2026, 11, 3), 1250, account: 'usd', home: 400),
      ]);
      expect(ledger.budgetService.spentAgainst(food, 2026, 11), 400);
    });

    test('a transfer fee counts as spending, the transfer itself not', () {
      final ledger = book(day(2026, 11, 15), [
        entryOf(
          't',
          day(2026, 11, 3),
          EntryType.transfer,
          5000,
          'bank',
          to: 'usd',
          received: 150,
          fee: 15,
        ),
      ]);
      expect(ledger.reportService.expense(2026, 11), 15);
    });
  });

  group('month-end forecast', () {
    test('this month is scaled by the days gone', () {
      final ledger = book(day(2026, 11, 20), const []);
      // 20 of 30 days gone: 6000 x 30 / 20 = 9000.
      expect(ledger.budgetService.forecast(6000, 2026, 11), 9000);
    });
    test('rounds to the nearest whole dollar', () {
      final ledger = book(day(2026, 11, 7), const []);
      // 1000 x 30 / 7 = 4285.7 -> 4286.
      expect(ledger.budgetService.forecast(1000, 2026, 11), 4286);
    });
    test('on the last day the forecast is what was spent', () {
      final ledger = book(day(2026, 11, 30), const []);
      expect(ledger.budgetService.forecast(7777, 2026, 11), 7777);
    });
    test('a month gone by or still to come forecasts what it holds', () {
      final ledger = book(day(2026, 11, 15), const []);
      expect(ledger.budgetService.forecast(4321, 2026, 10), 4321);
      expect(ledger.budgetService.forecast(0, 2026, 12), 0);
    });
    test('days gone are counted for the month length', () {
      final ledger = book(day(2026, 11, 15), const []);
      expect(ledger.budgetService.daysGone(2026, 11), (15, 30));
      // Other months count all their days: February 2026 has 28,
      // 2028 (leap) 29, December 31.
      expect(ledger.budgetService.daysGone(2026, 2), (28, 28));
      expect(ledger.budgetService.daysGone(2028, 2), (29, 29));
      expect(ledger.budgetService.daysGone(2026, 12), (31, 31));
    });
    test('in February of a leap year the pace uses 29 days', () {
      final ledger = book(day(2028, 2, 10), const []);
      // 1000 x 29 / 10 = 2900.
      expect(ledger.budgetService.forecast(1000, 2028, 2), 2900);
    });
  });

  group('carry-over of last month\'s leftover', () {
    Ledger withOctober(int spentInOctober, int spentInNovember) =>
        book(day(2026, 12, 5), [
          spend('o', day(2026, 10, 10), spentInOctober),
          spend('n', day(2026, 11, 10), spentInNovember),
        ]);

    test('without carry the allowance is the limit', () {
      final ledger = withOctober(6000, 0);
      expect(ledger.budgetService.allowance(food, 2026, 11), 10000);
    });

    test('with carry, last month\'s leftover is added', () {
      final ledger = withOctober(6000, 0);
      final carry = Budget('飲食', 10000, carry: true, since: day(2026, 10, 1));
      // 10000 - 6000 = 4000 left; 10000 + 4000 = 14000.
      expect(ledger.budgetService.allowance(carry, 2026, 11), 14000);
    });

    test('an overspent month leaves nothing, and takes nothing off', () {
      final ledger = withOctober(12000, 0);
      final carry = Budget('飲食', 10000, carry: true, since: day(2026, 10, 1));
      expect(ledger.budgetService.allowance(carry, 2026, 11), 10000);
    });

    test('only the month before counts, leftovers do not pile up', () {
      final ledger = withOctober(6000, 7500);
      final carry = Budget('飲食', 10000, carry: true, since: day(2026, 10, 1));
      // December: only November's leftover, 10000 - 7500 = 2500 -> 12500.
      expect(ledger.budgetService.allowance(carry, 2026, 12), 12500);
    });

    test('a month before the budget began is not carried', () {
      final ledger = withOctober(6000, 0);
      final carry = Budget('飲食', 10000, carry: true, since: day(2026, 11, 1));
      expect(ledger.budgetService.allowance(carry, 2026, 11), 10000);
    });

    test('a budget with no limit has no allowance to carry', () {
      final ledger = withOctober(6000, 0);
      final carry = Budget('飲食', 0, carry: true, since: day(2026, 10, 1));
      expect(ledger.budgetService.allowance(carry, 2026, 11), 0);
    });
  });

  group('setting a budget', () {
    test(
      'a new budget begins this month, warns at 80% and keeps nothing over',
      () {
        final ledger = book(day(2026, 11, 15), const []);
        ledger.budgetCommands.setBudget('飲食', 10000);
        final b = ledger.budgets.forCategory('飲食');
        expect(b.limit, 10000);
        expect(b.warning, 80);
        expect(b.carry, isFalse);
        expect(b.since, day(2026, 11, 1));
      },
    );
    test('changing it keeps its start, warning and carry', () {
      final ledger = book(day(2026, 11, 15), const []);
      ledger.budgetCommands.setBudget('飲食', 10000, warning: 90, carry: true);
      ledger.budgetCommands.setBudget('飲食', 12000);
      final b = ledger.budgets.forCategory('飲食');
      expect((b.limit, b.warning, b.carry), (12000, 90, true));
      expect(b.since, day(2026, 11, 1));
    });
    test('removing a budget removes it', () {
      final ledger = book(day(2026, 11, 15), const []);
      ledger.budgetCommands.setBudget('飲食', 10000);
      ledger.budgetCommands.removeBudget('飲食');
      expect(ledger.budgets.forCategory('飲食').limit, 0);
    });
  });
}
