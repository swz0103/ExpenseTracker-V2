import 'package:expense_tracker/src/core/ledger/cache/topic.dart';
import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/book.dart';

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

  test("an account's entries, newest first, both ends of a transfer", () {
    final book = Book(
      entries: [
        entry('a', amount: 300, date: DateTime.utc(2026, 9, 1)),
        entry('c', type: EntryType.transfer, amount: 200, to: 'cash'),
        entry('b', type: EntryType.income, amount: 500, account: 'cash'),
      ],
    );
    expect([for (final e in book.balances.entriesOf('bank')) e.id], ['c', 'a']);
    expect([for (final e in book.balances.entriesOf('cash')) e.id], ['b', 'c']);
    expect(book.balances.entriesOf('gone'), isEmpty);
  });

  test("an account's flow in a month, in and out apart", () {
    final book = Book(
      entries: [
        entry('old', amount: 999, date: DateTime.utc(2026, 9, 30)),
        entry('a', amount: 300),
        entry('b', type: EntryType.income, amount: 500),
        entry('c', type: EntryType.transfer, amount: 200, to: 'cash'),
      ],
    );
    // October: 500 in; 300 + 200 out. September's 999 is not counted.
    expect(book.balances.flowOf('bank', day), (inflow: 500, outflow: 500));
    // The cash account received the 200 transfer.
    expect(book.balances.flowOf('cash', day), (inflow: 200, outflow: 0));
    expect(book.balances.flowOf('bank', DateTime.utc(2026, 9, 1)), (
      inflow: 0,
      outflow: 999,
    ));
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

  test('a change to one account\'s entries leaves the others\' balances '
      'as they were, and moves its own', () {
    final book = Book(
      entries: [
        entry('a', amount: 300),
        entry('t', type: EntryType.transfer, amount: 200, to: 'cash'),
      ],
    );
    expect(book.balances.balance('bank'), 1000 - 300 - 200);
    expect(book.balances.balance('cash'), 50 + 200);
    book.entries.add(entry('b', amount: 100));
    book.cache.forget(const {Topic.entries});
    expect(book.balances.balance('bank'), 1000 - 300 - 200 - 100);
    expect(book.balances.balance('cash'), 250, reason: 'kept, and still so');
    // The transfer made smaller: both of its ends move.
    book.entries[1] = entry(
      't',
      type: EntryType.transfer,
      amount: 50,
      to: 'cash',
    );
    book.cache.forget(const {Topic.entries});
    expect(book.balances.balance('cash'), 50 + 50);
    expect(book.balances.balance('bank'), 1000 - 300 - 50 - 100);
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
    // Today is a Sunday, the first day of its week: nothing yet. The week
    // before began on Sunday the 27th and holds both entries.
    expect(weeks.last, (DateTime.utc(2026, 10, 4), 0));
    expect(weeks[2], (DateTime.utc(2026, 9, 27), -150));
    expect(weeks.first.$2, 0);
  });
}
