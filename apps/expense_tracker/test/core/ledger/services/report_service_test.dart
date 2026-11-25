import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/book.dart';

void main() {
  final lastMonth = DateTime.utc(2026, 9, 10);

  test("a month's income and spending count only that month", () {
    final book = Book(
      entries: [
        entry('a', amount: 300),
        entry('b', type: EntryType.income, amount: 900),
        entry('c', amount: 50, date: lastMonth),
      ],
    );
    expect(book.reports.income(2026, 10), 900);
    expect(book.reports.expense(2026, 10), 300);
    expect(book.reports.expense(2026, 9), 50);
    expect(book.reports.spentOn(day), 300);
  });

  test('the totals of a list count what counts today (D25)', () {
    final soon = DateTime.utc(2026, 10, 6);
    final book = Book(
      entries: [
        entry('lunch', amount: 120),
        entry('pay', type: EntryType.income, amount: 3000),
        entry('planned', amount: 500, date: soon),
      ],
    );
    final all = book.entries.all;
    // Today 10/4: 120 spent, 3000 earned; the 預定 500 on 10/6 not yet.
    expect(book.reports.totalsOf(all), (income: 3000, expense: 120));
    book.today = soon;
    // 120 + 500 = 620 once 10/6 comes.
    expect(book.reports.totalsOf(all), (income: 3000, expense: 620));
    expect(book.reports.totalsOf(const []), (income: 0, expense: 0));
  });

  test('spending up to a day of the month leaves the later days out', () {
    final book = Book(
      entries: [
        entry('a', amount: 300, date: DateTime.utc(2026, 10, 1)),
        entry('b', amount: 70, date: DateTime.utc(2026, 10, 3)),
      ],
    );
    expect(book.reports.expense(2026, 10, untilDay: 2), 300);
  });

  test("a stretch's spending is summed by category", () {
    final book = Book(
      categories: [Category('飲食', 'food', 0), Category('交通', 'bus', 0)],
      entries: [
        entry('a', amount: 100),
        entry('b', amount: 400, category: '交通'),
        entry('c', amount: 50),
      ],
    );
    expect(book.reports.spendingBetween(DateTime.utc(2026, 10), day), {
      '飲食': 150,
      '交通': 400,
    });
    expect(book.reports.totalsBetween(DateTime.utc(2026, 10), day), (0, 550));
  });

  test('tags are counted with their spending, most used first', () {
    final book = Book(
      entries: [
        entry('a', amount: 100, tags: ['旅行']),
        entry('b', amount: 40, tags: ['家用']),
        entry('c', amount: 60, tags: ['家用']),
      ],
    );
    expect(book.reports.tagStats, [('家用', 2, 100), ('旅行', 1, 100)]);
    expect(book.reports.tags, ['家用', '旅行']);
  });

  test('a 預定 entry joins the tags on its day, at midnight (D71)', () {
    // Today is 10/4: 1,000 on 10/1 counts; 300 on 10/6 is 預定, and so
    // is 50 tagged 露營 on 10/9.
    final book = Book(
      entries: [
        entry('a', amount: 1000, tags: ['旅行'], date: DateTime.utc(2026, 10)),
        entry('p', amount: 300, tags: ['旅行'], date: DateTime.utc(2026, 10, 6)),
        entry('q', amount: 50, tags: ['露營'], date: DateTime.utc(2026, 10, 9)),
      ],
    );
    expect(book.reports.tagStats, [('旅行', 1, 1000)]);
    expect(
      book.reports.tagsBetween(
        DateTime.utc(2026, 10),
        DateTime.utc(2026, 10, 31),
      ),
      [('旅行', 1000)],
    );
    // 露營 is offered to pick, after the tags in use.
    expect(book.reports.tags, ['旅行', '露營']);
    // The day rolls over to 10/6: 1,000 + 300 = 1,300 in two.
    book.today = DateTime.utc(2026, 10, 6);
    expect(book.reports.tagStats, [('旅行', 2, 1300)]);
  });

  test('what a person owes is what was lent less what came back', () {
    final book = Book(
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 1000),
        Account('amy', 'Amy', AccountKind.receivable, 0),
      ],
      entries: [
        entry(
          'lend1',
          type: EntryType.transfer,
          amount: 300,
          to: 'amy',
          date: DateTime.utc(2026, 9, 1),
        ),
        entry(
          'lend2',
          type: EntryType.transfer,
          amount: 200,
          to: 'amy',
          date: DateTime.utc(2026, 9, 5),
        ),
        entry(
          'back',
          type: EntryType.transfer,
          amount: 350,
          account: 'amy',
          to: 'bank',
          date: DateTime.utc(2026, 9, 9),
        ),
      ],
    );
    // The oldest is paid off first: 50 of the second is left.
    expect(
      [for (final (e, left) in book.reports.owedBy('amy')) (e.id, left)],
      [('lend2', 150)],
    );
  });

  test('the book starts on its first entry, or today when empty', () {
    expect(Book().reports.firstDay, day);
    expect(
      Book(entries: [entry('a', date: lastMonth)]).reports.firstDay,
      lastMonth,
    );
  });

  group('what a person owes agrees with their balance', () {
    test('a spending kept on the person\'s account lowers what is owed', () {
      final book = Book(
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 100000),
          Account('p', '小明', AccountKind.receivable, 0),
        ],
        entries: [
          entry(
            'l',
            type: EntryType.transfer,
            amount: 1000,
            to: 'p',
            date: DateTime.utc(2026, 10, 1),
          ),
          entry(
            'x',
            amount: 300,
            account: 'p',
            date: DateTime.utc(2026, 10, 2),
          ),
        ],
      );
      // 1000 lent, 300 taken off: 700, as the balance.
      expect(
        [for (final (e, left) in book.reports.owedBy('p')) (e.id, left)],
        [('l', 700)],
      );
      expect(book.balances.balance('p'), 700);
    });

    test('a person kept in US\$ owes what arrived, in US cents', () {
      final book = Book(
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 100000),
          Account('p', '小明', AccountKind.receivable, 0, currency: 'USD'),
        ],
        entries: [
          Entry(
            id: 'l',
            date: DateTime.utc(2026, 10, 1),
            type: EntryType.transfer,
            amount: 3200,
            account: 'bank',
            to: 'p',
            received: 10000,
          ),
        ],
      );
      expect(
        [for (final (e, left) in book.reports.owedBy('p')) (e.id, left)],
        [('l', 10000)],
      );
      expect(book.balances.balance('p'), 10000);
    });
  });

  group('edges review 11 found untested', () {
    test('spending up to a day counts that day; by account, only its own', () {
      final book = Book(
        entries: [
          entry('a', amount: 300, date: DateTime.utc(2026, 10, 1)),
          entry('b', amount: 70, date: DateTime.utc(2026, 10, 3)),
          entry(
            'c',
            amount: 5,
            account: 'cash',
            date: DateTime.utc(2026, 10, 3),
          ),
        ],
      );
      // Up to the 3rd: 300 + 70 + 5 = 375.
      expect(book.reports.expense(2026, 10, untilDay: 3), 375);
      expect(book.reports.expense(2026, 10, account: 'cash'), 5);
      expect(book.reports.expense(2026, 10, account: 'bank'), 370);
    });

    test('merchants: spending only, named only, largest first, with how '
        'many times', () {
      final book = Book(
        entries: [
          entry('a', amount: 100, merchant: '麵店'),
          entry('b', amount: 50, merchant: '麵店'),
          entry('c', amount: 400, merchant: '超市'),
          entry('d', amount: 999),
          entry('e', type: EntryType.income, amount: 800, merchant: '公司'),
        ],
      );
      expect(book.reports.merchantsBetween(DateTime.utc(2026, 10), day), [
        ('超市', 1, 400),
        ('麵店', 2, 150),
      ]);
      // Most used first.
      expect(book.reports.merchantStats, [('麵店', 2, 150), ('超市', 1, 400)]);
    });

    test('tags of a stretch, largest spending first', () {
      final book = Book(
        entries: [
          entry('a', amount: 100, tags: ['日常']),
          entry('b', amount: 500, tags: ['旅行']),
        ],
      );
      expect(book.reports.tagsBetween(DateTime.utc(2026, 10), day), [
        ('旅行', 500),
        ('日常', 100),
      ]);
    });

    test('what a person owed from the start is paid back first; newest '
        'first', () {
      final book = Book(
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 1000),
          // Owed 100 from the start.
          Account('amy', 'Amy', AccountKind.receivable, 100),
        ],
        entries: [
          for (final (id, d, n) in [('l1', 1, 300), ('l2', 2, 200)])
            entry(
              id,
              type: EntryType.transfer,
              amount: n,
              to: 'amy',
              date: DateTime.utc(2026, 9, d),
            ),
          entry(
            'back',
            type: EntryType.transfer,
            amount: 150,
            account: 'amy',
            to: 'bank',
            date: DateTime.utc(2026, 9, 3),
          ),
        ],
      );
      // 150 back: 100 of the start, then 50 of l1. Newest first.
      expect(
        [for (final (e, left) in book.reports.owedBy('amy')) (e.id, left)],
        [('l2', 200), ('l1', 250)],
      );
    });

    test('what a person owes is asked again on a new day', () {
      final book = Book(
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 1000),
          Account('amy', 'Amy', AccountKind.receivable, 0),
        ],
        entries: [
          entry(
            'l',
            type: EntryType.transfer,
            amount: 300,
            to: 'amy',
            date: DateTime.utc(2026, 10, 6),
          ),
        ],
      );
      expect(book.reports.owedBy('amy'), isEmpty);
      book.today = DateTime.utc(2026, 10, 6);
      expect(
        [for (final (e, n) in book.reports.owedBy('amy')) (e.id, n)],
        [('l', 300)],
      );
    });

    test('categories by use: this month and the last, of the kind asked, '
        'most used first', () {
      final book = Book(
        categories: [
          // 購物 before 交通: only September's use puts 交通 first.
          Category('飲食', 'food', 0),
          Category('購物', 'bag', 0),
          Category('交通', 'bus', 0),
          Category('薪水', 'salary', 0, income: true),
        ],
        entries: [
          // September (last month) and October count; August does not.
          entry('a', category: '交通', date: DateTime.utc(2026, 9, 10)),
          entry('b', category: '交通', date: DateTime.utc(2026, 10, 1)),
          entry('c', category: '購物', date: DateTime.utc(2026, 10, 2)),
          for (final i in [1, 2, 3])
            entry('old$i', category: '飲食', date: DateTime.utc(2026, 8, i)),
          for (final i in [1, 2, 3])
            entry(
              'pay$i',
              type: EntryType.income,
              category: '購物',
              date: DateTime.utc(2026, 10, i),
            ),
        ],
      );
      // 交通 2, 購物 1 (the incomes filed under it not counted), 飲食 0.
      expect(book.reports.categoriesByUse(income: false), ['交通', '購物', '飲食']);
    });

    test("a month's dividends count cash dividends only", () {
      final book = Book(
        entries: [
          Entry(
            id: 'buy',
            date: DateTime.utc(2026, 10, 1),
            type: EntryType.buy,
            amount: 10000,
            account: 'bank',
            holding: '2330',
            shares: 10,
          ),
          Entry(
            id: 'div',
            date: DateTime.utc(2026, 10, 2),
            type: EntryType.dividend,
            amount: 500,
            tax: 10,
            account: 'bank',
            holding: '2330',
          ),
          Entry(
            id: 'cut',
            date: DateTime.utc(2026, 10, 3),
            type: EntryType.dividend,
            amount: 2000,
            account: 'bank',
            holding: '2330',
            shares: -2,
          ),
        ],
      );
      // 500 - 10 of the dividend; the purchase and the reduction are not
      // dividends.
      expect(book.reports.dividends(2026, 10), 490);
    });
  });
}
