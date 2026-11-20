import 'package:expense_tracker/src/core/ledger/models/models.dart';
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
}
