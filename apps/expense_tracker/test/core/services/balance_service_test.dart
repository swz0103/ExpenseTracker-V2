import 'package:expense_tracker/src/core/ledger/cache/topic.dart';
import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'book.dart';

void main() {
  test('a balance is the opening sum and every entry up to the day', () {
    final book = Book(
      entries: [
        entry('a', amount: 300, date: DateTime.utc(2026, 9, 1)),
        entry('b', type: EntryType.income, amount: 500),
        entry('c', type: EntryType.transfer, amount: 200, to: 'cash'),
      ],
    );
    expect(book.balances.balance('bank'), 1000 - 300 + 500 - 200);
    expect(book.balances.balance('cash'), 50 + 200);
    expect(
      book.balances.balance('bank', until: DateTime.utc(2026, 9, 30)),
      700,
    );
  });

  test('an account the book has none of has a balance of nothing', () {
    expect(Book().balances.balance('gone'), 0);
  });

  test('a balance is worked out again only after its topics change', () {
    final book = Book(entries: [entry('a', amount: 300)]);
    expect(book.balances.balance('bank'), 700);
    book.entries.add(entry('b', amount: 100));
    // Still the answer worked out before: nothing said the entries changed.
    expect(book.balances.balance('bank'), 700);
    book.cache.forget(const {Topic.budgets});
    expect(book.balances.balance('bank'), 700);
    book.cache.forget(const {Topic.entries});
    expect(book.balances.balance('bank'), 600);
  });

  test('a foreign account without a rate is left out of the worth', () {
    final book = Book(
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 1000),
        Account('usd', '美元', AccountKind.bank, 10000, currency: 'USD'),
      ],
    );
    expect(book.balances.unrated.map((a) => a.id), ['usd']);
    expect(book.balances.assets, 1000);
  });

  test('a foreign account counts at its rate once there is one', () {
    final book = Book(
      accounts: const [
        Account('usd', '美元', AccountKind.bank, 10000, currency: 'USD'),
      ],
      rates: {'USD': 32},
    );
    expect(book.balances.unrated, isEmpty);
    // 10000 cents is 100 dollars.
    expect(book.balances.assets, 3200);
  });

  test('what is owed on cards and loans is told apart from assets', () {
    final book = Book(
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 1000),
        Account('card', '卡', AccountKind.card, -300),
        Account('loan', '房貸', AccountKind.loan, -5000),
      ],
    );
    expect(book.balances.assets, 1000);
    expect(book.balances.cardDebt, 300);
    expect(book.balances.loanDebt, 5000);
    expect(book.balances.netWorthAt(day), 1000 - 300 - 5000);
  });

  test('each week of the last four shows how the account moved', () {
    final book = Book(
      entries: [
        entry('a', amount: 100, date: DateTime.utc(2026, 9, 30)),
        entry('b', amount: 50, date: DateTime.utc(2026, 10, 3)),
        entry('c', amount: 999, date: DateTime.utc(2026, 8, 1)),
      ],
    );
    final weeks = book.balances.weeklyChanges('bank');
    expect(weeks, hasLength(4));
    // Today is a Sunday; this week began on Monday the 28th.
    expect(weeks.last, (DateTime.utc(2026, 9, 28), -150));
    expect(weeks.first.$2, 0);
  });
}
