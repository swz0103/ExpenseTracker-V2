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

  group('which budgets a saved entry touches, and whether it went over '
      '(review 32, finding 8)', () {
    Book book(List<Budget> budgets) => Book(
      categories: [
        Category('飲食', 'food', 0xFF111111),
        Category('早餐', 'food', 0xFF222222, parent: '飲食'),
        Category('交通', 'car', 0xFF333333),
      ],
      budgets: budgets,
      entries: [
        entry('a', amount: 900, category: '早餐', tags: ['家用']),
      ],
    );

    test('a parent budget counts its subcategory (D54)', () {
      final b = book(const [Budget('飲食', 800)]);
      final breakfast = b.entries.byId('a')!;
      expect(b.budgets.touches(const Budget('飲食', 800), breakfast), isTrue);
      expect(b.budgets.touches(const Budget('交通', 800), breakfast), isFalse);
      // 900 spent against 800.
      expect(b.budgets.overAfter(breakfast), isTrue);
    });

    test('a tag budget is kept as #tag and matches the tag', () {
      final b = book(const [Budget('#家用', 500)]);
      final breakfast = b.entries.byId('a')!;
      expect(b.budgets.touches(const Budget('#家用', 500), breakfast), isTrue);
      expect(b.budgets.touches(const Budget('家用', 500), breakfast), isFalse);
      // 900 against 500.
      expect(b.budgets.overAfter(breakfast), isTrue);
    });

    test('the total counts any spending; income touches none', () {
      final b = book(const [Budget(allSpending, 1000), Budget('交通', 10)]);
      final breakfast = b.entries.byId('a')!;
      // 900 of 1000 spent: not over; 交通 is over, but untouched.
      expect(b.budgets.overAfter(breakfast), isFalse);
      final pay = entry('p', type: EntryType.income, amount: 5000);
      expect(b.budgets.touches(const Budget(allSpending, 1), pay), isFalse);
      expect(b.budgets.overAfter(pay), isFalse);
    });

    test('a budget of nothing is never over', () {
      final b = book(const [Budget('飲食', 0)]);
      expect(b.budgets.overAfter(b.entries.byId('a')!), isFalse);
    });
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

  group('edges review 11 found untested', () {
    test('a forecast rounds half away from zero', () {
      // 10 spent in 4 of 31 days: 10 x 31 / 4 = 77.5 -> 78.
      expect(Book().budgets.forecast(10, 2026, 10), 78);
    });

    test('on the month\'s last day the forecast is what was spent', () {
      final book = Book()..today = DateTime.utc(2026, 10, 31);
      expect(book.budgets.forecast(400, 2026, 10), 400);
      // Refunds past the spending: what was spent, not floored at 0.
      expect(book.budgets.forecast(-100, 2026, 10), -100);
    });

    test('an overspent last month carries nothing, a refund-only one '
        'nothing to a budget of 0', () {
      final book = Book(
        entries: [
          entry('a', amount: 1300, date: DateTime.utc(2026, 9, 3)),
          entry(
            'r',
            type: EntryType.income,
            amount: 200,
            category: '交通',
            refundOf: 'gone',
            date: DateTime.utc(2026, 9, 4),
          ),
        ],
      );
      // 1,000 - 1,300 left: below nothing, so 1,000 only.
      expect(
        book.budgets.allowance(Budget('飲食', 1000, carry: true), 2026, 10),
        1000,
      );
      // 交通 spent -200 in September: a budget of 0 stays 0.
      expect(book.budgets.allowance(Budget('交通', 0, carry: true), 2026, 10), 0);
    });

    test('a budget set from last month carries its leftover', () {
      final book = Book(
        entries: [entry('a', amount: 300, date: DateTime.utc(2026, 9, 3))],
      );
      final since = Budget(
        '飲食',
        1000,
        carry: true,
        since: DateTime.utc(2026, 9),
      );
      // 1,000 + (1,000 - 300).
      expect(book.budgets.allowance(since, 2026, 10), 1700);
    });

    test('a purchase on the 1st is this month\'s own, scaled with its '
        'refund', () {
      final book = Book(
        entries: [
          entry('buy', amount: 1000, date: DateTime.utc(2026, 10, 1)),
          entry(
            'back',
            type: EntryType.income,
            amount: 400,
            refundOf: 'buy',
            date: DateTime.utc(2026, 10, 2),
          ),
        ],
      );
      // 600 own spending in 4 of 31 days: 600 x 31 / 4 = 4,650.
      expect(book.budgets.forecast(600, 2026, 10), 4650);
    });

    test('a 預定 refund of an earlier purchase is not taken off yet', () {
      final book = Book(
        entries: [
          entry('buy', amount: 1000, date: DateTime.utc(2026, 9, 20)),
          entry('x', amount: 100, date: DateTime.utc(2026, 10, 2)),
          entry(
            'back',
            type: EntryType.income,
            amount: 300,
            refundOf: 'buy',
            date: DateTime.utc(2026, 10, 6),
          ),
        ],
      );
      // 100 x 31 / 4 = 775; the refund on 10/6 is not here yet.
      expect(book.budgets.forecast(100, 2026, 10), 775);
    });

    test('this month: what can be spent a day over the days left, today '
        'included', () {
      final pace = Book().budgets.pace(100, 3100, 2026, 10) as CurrentPace;
      // 3,000 left over 31 - 4 + 1 = 28 days: 107.1 -> 107.
      expect((pace.daysLeft, pace.perDay), (28, 107));
    });
  });

  test('the forecast shows from day 7; heading for exactly the budget is '
      'not over it (mutation review 11)', () {
    final book = Book()..today = DateTime.utc(2026, 10, 7);
    // 700 in 7 of 31 days: 700 x 31 / 7 = 3,100, the whole budget.
    final pace = book.budgets.pace(700, 3100, 2026, 10) as CurrentPace;
    expect(pace.forecast, 3100);
    expect(pace.overBudget, isFalse);
  });
}
