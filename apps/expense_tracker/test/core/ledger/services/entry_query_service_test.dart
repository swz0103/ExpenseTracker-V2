import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/book.dart';
import '../../../support/fuzz/search_fuzz.dart';

void main() {
  searchFuzz();

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
    // D79: the purchase a refund (or its draft) gives back.
    final back = book.entries.byId('back');
    expect(book.queries.originalOf(back), same(bought));
    expect(book.queries.originalOf(bought), isNull);
    expect(book.queries.originalOf(null), isNull);
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

  test('typing on narrows what was found; a change is searched afresh', () {
    final ledger = Ledger(
      today: DateTime.utc(2026, 10, 4),
      accounts: [Account('a', '銀行', AccountKind.bank, 0)],
      categories: const [],
      entries: [
        entry('lunch', account: 'a', merchant: '午餐', amount: 120),
        entry('nap', account: 'a', merchant: '午睡', amount: 12),
        entry('dinner', account: 'a', merchant: '晚餐', amount: 1200),
      ],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    final queries = ledger.entryQueryService;
    List<String> found(String words) => [
      for (final e in queries.search(words)) e.id,
    ];
    expect(found('午'), ['nap', 'lunch']);
    // Longer words: among what 午 found.
    expect(found('午餐'), ['lunch']);
    // Words that could be an amount are matched whole, never narrowed:
    // 12 after 1 finds the entry of 12, which 1 found only in its text.
    expect(found('1'), isEmpty);
    expect(found('12'), ['nap']);
    expect(found('120'), ['lunch']);
    // A save: the month's text is worked out again, the rest kept.
    ledger.entryCommands.add(
      entry(
        'late',
        account: 'a',
        merchant: '午後',
        date: DateTime.utc(2026, 10, 4),
      ),
    );
    expect(found('午'), ['late', 'nap', 'lunch']);
    expect(found('午後'), ['late']);
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

  group('a 預定 entry is not recent nor the latest (D71)', () {
    // Today is 10/4; 10/6 and 10/8 are 預定.
    final soon = DateTime.utc(2026, 10, 6);
    final later = DateTime.utc(2026, 10, 8);

    test('usual spending and transfers leave it out', () {
      final book = Book(
        entries: [
          for (var i = 0; i < 2; i++)
            entry(
              'm$i',
              merchant: '咖啡',
              date: day.subtract(Duration(days: i)),
            ),
          entry('p', merchant: '咖啡', date: soon),
          entry('t0', type: EntryType.transfer, to: 'cash', amount: 500),
          entry(
            't1',
            type: EntryType.transfer,
            to: 'cash',
            amount: 500,
            date: later,
          ),
        ],
      );
      // Two alike by today, not three: not usual yet.
      expect(book.queries.usual(), isEmpty);
      // One transfer by today, not two.
      expect(book.queries.usualTransfers(), isEmpty);
      book.today = later;
      // On 10/8 three spendings alike, the latest 10/6's; two transfers.
      expect(book.queries.usual().map((e) => e.id), ['p']);
      expect(book.queries.usualTransfers().map((e) => e.id), ['t1']);
    });

    test('the last used category comes from what counts today', () {
      final book = Book(
        entries: [
          entry('a', merchant: '捷運', category: '交通'),
          entry('b', merchant: '捷運', category: '通勤', date: soon),
          entry('c', merchant: '書店', date: later),
        ],
      );
      expect(book.queries.lastAt('捷運')?.id, 'a');
      expect(book.queries.categoryAt('捷運'), '交通');
      // 書店 is known, to pick, though used only on a 預定 entry: last.
      expect(book.queries.merchants, ['捷運', '書店']);
      book.today = soon;
      expect(book.queries.categoryAt('捷運'), '通勤');
    });
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
