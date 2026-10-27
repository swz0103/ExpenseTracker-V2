import 'package:expense_tracker/src/core/ledger/batch.dart';
import 'package:expense_tracker/src/features/import/model/exchange.dart';
import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing: only remembers the batches it was handed.
final class _Batches implements Journal {
  final kept = <Batch>[];

  @override
  Future<void> keep(Batch batch) async => kept.add(batch);

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  final day = DateTime.utc(2026, 10, 4);
  late _Batches journal;

  Ledger book({List<Entry> entries = const [], List<Budget>? budgets}) {
    journal = _Batches();
    return Ledger(
      today: day,
      accounts: [
        const Account('bank', '銀行', AccountKind.bank, 100000),
        Account(
          'card',
          '卡',
          AccountKind.card,
          0,
          closingDay: 25,
          dueDay: 10,
          closes: {DateTime.utc(2026, 10, 25): DateTime.utc(2026, 10, 23)},
        ),
      ],
      categories: const [
        Category('飲食', 'food', Color(0xFF5C9A83)),
        Category('居家', 'home', Color(0xFF5B8DB0)),
      ],
      entries: entries,
      holdings: const [],
      budgets: budgets ?? const [],
      recurring: const [],
      journal: journal,
    );
  }

  Entry spend(String id, int amount, {String category = '飲食'}) => Entry(
    id: id,
    date: day,
    type: EntryType.expense,
    amount: amount,
    account: 'bank',
    category: category,
  );

  test('editing a card keeps its moved closes and billing history', () async {
    final ledger = book();
    // The form builds the account afresh, without the dates it hides.
    ledger.updateAccount(
      const Account(
        'card',
        '新名字',
        AccountKind.card,
        0,
        closingDay: 5,
        dueDay: 20,
      ),
    );
    final card = ledger.account('card');
    expect(card.name, '新名字');
    expect(card.closes, {
      DateTime.utc(2026, 10, 25): DateTime.utc(2026, 10, 23),
    });
    expect(card.history.single.closingDay, 25);

    // Changed again before that close: the first days still hold until
    // the first close on the newest day.
    ledger.updateAccount(card.copyWith(closingDay: 15, dueDay: 30));
    final again = ledger.account('card');
    expect(again.history.single.closingDay, 25);
    expect(again.history.single.until.day, 15);
    await ledger.settled;
  });

  test('a delete that would oversell is refused, not thrown', () async {
    final buy = Entry(
      id: 'buy',
      date: DateTime.utc(2026, 9, 1),
      type: EntryType.buy,
      amount: 1000,
      account: 'bank',
      holding: '2330',
      shares: 10,
    );
    final sell = Entry(
      id: 'sell',
      date: DateTime.utc(2026, 9, 2),
      type: EntryType.sell,
      amount: 1200,
      account: 'bank',
      holding: '2330',
      shares: 10,
    );
    final ledger = book(entries: [buy, sell]);
    expect(ledger.remove('buy'), isNull);
    expect(ledger.problem.value, isA<SharesShort>());
    expect(ledger.entries, hasLength(2));
    expect(ledger.trash, isEmpty);
    await ledger.settled;
    expect(journal.kept, isEmpty);
  });

  test('taken and reserved category names are refused', () {
    final ledger = book();
    for (final name in ['飲食', '全部支出', '轉帳', '#旅遊', ' ']) {
      expect(ledger.categoryNameFree(name), isFalse, reason: name);
    }
    expect(ledger.categoryNameFree('飲食', except: '飲食'), isTrue);
    ledger.addCategory(const Category('轉帳', 'other', Color(0xFF000000)));
    expect(ledger.problem.value, isA<NameTaken>());
    expect(ledger.categories, hasLength(2));
  });

  test('renaming onto a name that has a budget leaves one budget', () {
    final ledger = book(
      budgets: const [Budget('#旅遊', 5000), Budget('#出差', 3000)],
    );
    ledger.renameTag('出差', '旅遊');
    expect([for (final b in ledger.budgets) b.category], ['#旅遊']);
  });

  test('merged categories join an entry split between them', () {
    final split = Entry(
      id: 's',
      date: day,
      type: EntryType.expense,
      amount: 300,
      account: 'bank',
      category: '飲食',
      parts: const [('飲食', 200), ('居家', 100)],
    );
    final merged = split.withCategory('飲食', from: '居家');
    expect(merged.parts, isEmpty);
    expect(merged.category, '飲食');
  });

  test('a photo and many edits are each kept as one change', () async {
    final ledger = book(entries: [spend('a', 100), spend('b', 200)]);
    ledger.add(spend('c', 50), receipt: 'c.etr');
    await ledger.settled;
    expect(journal.kept, hasLength(1));
    expect(journal.kept.single.receipts, {'c': 'c.etr'});
    expect(ledger.receiptOf('c'), 'c.etr');

    journal.kept.clear();
    expect(ledger.recategorize(ledger.entries, '居家'), 3);
    await ledger.settled;
    expect(journal.kept, hasLength(1));
    expect(journal.kept.single.entries, hasLength(3));
  });

  test('a statement moves on at midnight with nothing changed', () {
    var now = DateTime.utc(2026, 10, 25);
    final ledger = Ledger(
      today: now,
      clock: () => now,
      accounts: const [
        Account('card', '卡', AccountKind.card, 0, closingDay: 25, dueDay: 10),
      ],
      categories: const [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    final card = ledger.account('card');
    // A statement closes at the end of its day.
    expect(ledger.statement(card).$2, DateTime.utc(2026, 9, 25));
    now = DateTime.utc(2026, 10, 26);
    expect(ledger.statement(card).$2, DateTime.utc(2026, 10, 25));
  });

  test('an undone delete is not brought back twice', () {
    final ledger = book(entries: [spend('a', 100)]);
    final removed = ledger.remove('a')!;
    expect(ledger.restore(removed), isTrue);
    expect(ledger.restore(removed), isFalse);
    expect(ledger.entries, hasLength(1));
    expect(ledger.trash, isEmpty);
  });

  test('a category from before the name rules can still be archived', () {
    final ledger = Ledger(
      today: day,
      accounts: const [],
      categories: const [Category('轉帳', 'other', Color(0xFF000000))],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    ledger.updateCategory('轉帳', ledger.category('轉帳').copyWith(archived: true));
    expect(ledger.category('轉帳').archived, isTrue);
    expect(ledger.problem.value, isNull);
  });

  test('an import adds a name and an account once', () {
    final ledger = book();
    ledger.addAll(
      [spend('x', 10, category: '寵物')],
      accounts: const [
        Account('bank', '重複的銀行', AccountKind.bank, 0),
        Account('new', '新帳戶', AccountKind.bank, 0),
      ],
      categories: const [
        Category('寵物', 'pet', Color(0xFF123456)),
        Category('寵物', 'pet', Color(0xFF123456)),
        Category('轉帳', 'other', Color(0xFF123456)),
      ],
    );
    expect([for (final a in ledger.accounts) a.id], ['bank', 'card', 'new']);
    expect(ledger.categories.where((c) => c.name == '寵物'), hasLength(1));
    expect(ledger.categories.where((c) => c.name == '轉帳'), isEmpty);
  });

  test('a reduction of more shares than held is refused', () {
    final ledger = book();
    final cut = Entry(
      id: 'cut',
      date: day,
      type: EntryType.dividend,
      amount: 100,
      account: 'bank',
      holding: '2330',
      shares: -10,
    );
    expect(() => ledger.add(cut), throwsStateError);
    expect(ledger.entries, isEmpty);
    // A book that already holds one still opens, without it.
    final kept = book(entries: [cut]);
    expect(kept.holding('2330'), isNull);
  });

  test("last month's unbooked item is still due", () {
    final rent = Recurring(
      id: 'rent',
      name: '房租',
      amount: 12000,
      day: 30,
      account: 'bank',
      category: '居家',
    );
    final paid = Entry(
      id: 'p',
      date: DateTime.utc(2026, 8, 30),
      type: EntryType.expense,
      amount: 12000,
      account: 'bank',
      category: '居家',
      recurring: 'rent',
    );
    final ledger = Ledger(
      today: DateTime.utc(2026, 10, 2),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 0)],
      categories: const [],
      entries: [paid],
      holdings: const [],
      budgets: const [],
      recurring: [rent],
    );
    expect(ledger.pendingDate(rent), DateTime.utc(2026, 9, 30));
    expect(ledger.due, [rent]);
    // A new item is not due for months before it was ever booked.
    final fresh = Ledger(
      today: DateTime.utc(2026, 10, 2),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 0)],
      categories: const [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: [rent],
    );
    expect(fresh.pendingDate(rent), DateTime.utc(2026, 10, 30));
  });

  test('a CSV keeps average-cost sales, spaced tags and = in names', () {
    final buy = Entry(
      id: 'b',
      date: DateTime.utc(2026, 9, 1),
      type: EntryType.buy,
      amount: 1000,
      account: 'bank',
      holding: '2330',
      shares: 10,
    );
    final sell = Entry(
      id: 's',
      date: DateTime.utc(2026, 9, 2),
      type: EntryType.sell,
      amount: 600,
      account: 'bank',
      holding: '2330',
      shares: 5,
      average: true,
    );
    final lunch = Entry(
      id: 'l',
      date: DateTime.utc(2026, 9, 3),
      type: EntryType.expense,
      amount: 80,
      account: 'bank',
      category: 'A=B',
      tags: const ['家用 午餐', '公司'],
    );
    final from = book(entries: [buy, sell, lunch]);
    final csv = toCsv(from, from.entries);
    final into = book();
    final found = importCsv(into, csv, fallback: 'bank');
    expect(found.problems, isEmpty);
    final back = {for (final e in found.entries) e.type: e};
    expect(back[EntryType.sell]!.average, isTrue);
    final expense = back[EntryType.expense]!;
    expect(expense.tags, ['家用 午餐', '公司']);
    expect(expense.category, 'A=B');
    expect(expense.parts, isEmpty);
  });
}
