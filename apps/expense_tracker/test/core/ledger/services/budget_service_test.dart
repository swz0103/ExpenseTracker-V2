import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/services/budget_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/book.dart';

void main() {
  test('this month has the days up to today gone; others all of theirs', () {
    final book = Book();
    expect(book.budgets.daysGone(2026, 10), (4, 31));
    expect(book.budgets.daysGone(2026, 9), (30, 30));
  });

  test('a forecast keeps the pace so far to the end of the month', () {
    final book = Book();
    expect(book.budgets.forecast(400, 2026, 10), 3100);
    expect(book.budgets.forecast(400, 2026, 9), 400);
  });

  test('a budget counts all spending, its tag or its category', () {
    final book = Book(
      entries: [
        entry('a', amount: 100, tags: ['旅行']),
        entry('b', amount: 40, category: '交通'),
      ],
    );
    expect(book.budgets.spentAgainst(Budget(allSpending, 1000), 2026, 10), 140);
    expect(book.budgets.spentAgainst(Budget('#旅行', 1000), 2026, 10), 100);
    expect(book.budgets.spentAgainst(Budget('交通', 1000), 2026, 10), 40);
  });

  test("a carried budget adds last month's leftover, never more", () {
    final book = Book(
      entries: [entry('a', amount: 300, date: DateTime.utc(2026, 9, 3))],
    );
    final carried = Budget('飲食', 1000, carry: true);
    expect(book.budgets.allowance(carried, 2026, 10), 1700);
    expect(book.budgets.allowance(Budget('飲食', 1000), 2026, 10), 1000);
    // Set this month: there was no budget to carry from last month.
    final fresh = Budget(
      '飲食',
      1000,
      carry: true,
      since: DateTime.utc(2026, 10),
    );
    expect(book.budgets.allowance(fresh, 2026, 10), 1000);
  });

  group('the month-end forecast (D64)', () {
    test('bought last month, refunded this month: never below nothing', () {
      final book = Book(
        entries: [
          entry('a', amount: 3000, date: DateTime.utc(2026, 9, 20)),
          entry(
            'b',
            type: EntryType.income,
            amount: 3000,
            date: DateTime.utc(2026, 10, 3),
            refundOf: 'a',
          ),
        ],
      )..today = DateTime.utc(2026, 10, 20);
      final spent = book.reports.expense(2026, 10);
      expect(spent, -3000);
      // Own spending 0 x 31 / 20 = 0, the refund -3000 not scaled:
      // -3000, held at 0.
      expect(book.budgets.forecast(spent, 2026, 10), 0);
    });

    test('the month\'s own spending is scaled, an earlier month\'s refund '
        'only counted', () {
      final book = Book(
        entries: [
          entry('a', amount: 1000, date: DateTime.utc(2026, 9, 20)),
          entry('x', amount: 2000, date: DateTime.utc(2026, 10, 2)),
          entry(
            'b',
            type: EntryType.income,
            amount: 1000,
            date: DateTime.utc(2026, 10, 3),
            refundOf: 'a',
          ),
        ],
      )..today = DateTime.utc(2026, 10, 10);
      final spent = book.reports.expense(2026, 10);
      expect(spent, 1000);
      // Own 2000 x 31 / 10 = 6200, less the refund 1000: 5200.
      expect(book.budgets.forecast(spent, 2026, 10), 5200);
    });

    test('a refund of this month\'s own purchase is scaled with it', () {
      final book = Book(
        entries: [
          entry('x', amount: 2000, date: DateTime.utc(2026, 10, 2)),
          entry(
            'b',
            type: EntryType.income,
            amount: 500,
            date: DateTime.utc(2026, 10, 3),
            refundOf: 'x',
          ),
        ],
      )..today = DateTime.utc(2026, 10, 10);
      // (2000 - 500) x 31 / 10 = 4650.
      expect(book.budgets.forecast(1500, 2026, 10), 4650);
    });
  });

  group('the pace the budget page shows', () {
    test('this month: a day\'s allowance, the days left and the forecast '
        'from day 7', () {
      final book = Book()..today = DateTime.utc(2026, 10, 10);
      final pace = book.budgets.pace(3000, 10000, 2026, 10) as CurrentPace;
      // 10000 - 3000 = 7000 over 31 - 10 + 1 = 22 days: 318 a day.
      expect(pace.daysLeft, 22);
      expect(pace.perDay, 318);
      // 3000 x 31 / 10 = 9300, under 10000.
      expect(pace.forecast, 9300);
      expect(pace.overBudget, isFalse);
      expect(
        (book.budgets.pace(4000, 10000, 2026, 10) as CurrentPace).overBudget,
        isTrue,
      );
    });

    test('before day 7 there is no forecast; overspent leaves 0 a day', () {
      final book = Book()..today = DateTime.utc(2026, 10, 6);
      final pace = book.budgets.pace(12000, 10000, 2026, 10) as CurrentPace;
      expect(BudgetService.forecastFrom, 7);
      expect(pace.forecast, isNull);
      expect(pace.overBudget, isFalse);
      expect(pace.perDay, 0);
    });

    test('a month gone by: spent a day and saved', () {
      final pace = Book().budgets.pace(6000, 10000, 2026, 9) as PastPace;
      // 6000 / 30 = 200 a day; 10000 - 6000 = 4000 saved.
      expect((pace.days, pace.perDay, pace.saved), (30, 200, 4000));
    });
  });

  test('a parent category\'s budget counts its subcategories and their '
      'split parts (D54)', () {
    final book = Book(
      categories: [
        Category('飲食', 'food', 0xFF111111),
        Category('早餐', 'food', 0xFF111111, parent: '飲食'),
      ],
      entries: [
        entry('a', amount: 100),
        entry('b', amount: 50, category: '早餐'),
        Entry(
          id: 'c',
          date: day,
          type: EntryType.expense,
          amount: 80,
          account: 'bank',
          category: '交通',
          parts: const [('交通', 60), ('早餐', 20)],
        ),
      ],
    );
    // 100 + 50 + 20 = 170; 早餐's own budget 50 + 20 = 70.
    expect(book.budgets.spentAgainst(Budget('飲食', 1000), 2026, 10), 170);
    expect(book.budgets.spentAgainst(Budget('早餐', 1000), 2026, 10), 70);
  });
}
