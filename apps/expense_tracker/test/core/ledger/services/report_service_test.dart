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
}
