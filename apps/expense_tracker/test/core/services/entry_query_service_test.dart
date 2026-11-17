import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'book.dart';

void main() {
  test('a group is led by its spending, the rest stand behind it', () {
    final paid = entry('paid', amount: 600, group: 'g');
    final forAmy = entry(
      'amy',
      type: EntryType.transfer,
      amount: 200,
      to: 'cash',
      group: 'g',
    );
    final alone = entry('alone');
    final book = Book(entries: [forAmy, paid, alone]);
    expect(book.queries.groupOf(forAmy).map((e) => e.id), ['paid', 'amy']);
    expect(book.queries.groupLead(forAmy).id, 'paid');
    expect(book.queries.isGroupTail(forAmy), isTrue);
    expect(book.queries.isGroupTail(paid), isFalse);
    expect(book.queries.groupOf(alone), [alone]);
  });

  test('a refund takes from what is left to refund', () {
    final bought = entry('bought', amount: 500);
    final book = Book(
      entries: [
        bought,
        entry('back', type: EntryType.income, amount: 120, refundOf: 'bought'),
      ],
    );
    expect(book.queries.refunded(bought), 120);
    expect(book.queries.refundable(bought), 380);
  });

  test('a search finds words in any field, and an amount, newest first', () {
    final book = Book(
      entries: [
        entry('old', merchant: '便當店', date: DateTime.utc(2026, 9, 1)),
        entry('new', merchant: '便當店'),
        entry('tagged', tags: ['家用']),
        entry('priced', amount: 4321),
      ],
    );
    expect(book.queries.search('便當').map((e) => e.id), ['new', 'old']);
    expect(book.queries.search('家用').map((e) => e.id), ['tagged']);
    expect(book.queries.search('4321').map((e) => e.id), ['priced']);
    expect(book.queries.search('沒有'), isEmpty);
  });

  test('spending made alike three times lately is usual', () {
    final alike = [
      for (var i = 0; i < 3; i++)
        entry(
          'm$i',
          merchant: '咖啡',
          date: day.subtract(Duration(days: i)),
        ),
    ];
    final book = Book(
      entries: [
        ...alike,
        entry('once', merchant: '書店'),
      ],
    );
    expect(book.queries.usual().map((e) => e.id), ['m0']);
    final twice = Book(entries: alike.sublist(1));
    expect(twice.queries.usual(), isEmpty);
  });

  test('merchants come most used first, with the category last used', () {
    final book = Book(
      entries: [
        entry(
          'a',
          merchant: '捷運',
          category: '交通',
          date: DateTime.utc(2026, 9, 1),
        ),
        entry('b', merchant: '捷運', category: '通勤'),
        entry('c', merchant: '咖啡'),
      ],
    );
    expect(book.queries.merchants, ['捷運', '咖啡']);
    expect(book.queries.categoryAt('捷運'), '通勤');
    expect(book.queries.categoryAt('沒去過'), isNull);
  });

  test("a stock's trades come newest first", () {
    final book = Book(
      entries: [
        Entry(
          id: 'b1',
          date: DateTime.utc(2026, 9, 1),
          type: EntryType.buy,
          amount: 1000,
          account: 'bank',
          holding: '2330',
          shares: 1,
        ),
        Entry(
          id: 'b2',
          date: DateTime.utc(2026, 9, 9),
          type: EntryType.buy,
          amount: 1000,
          account: 'bank',
          holding: '2330',
          shares: 1,
        ),
        Entry(
          id: 'x',
          date: day,
          type: EntryType.buy,
          amount: 1,
          account: 'bank',
          holding: '0050',
          shares: 1,
        ),
      ],
    );
    expect(book.queries.tradesOf('2330').map((e) => e.id), ['b2', 'b1']);
  });
}
