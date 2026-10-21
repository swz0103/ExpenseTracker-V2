import 'package:expense_tracker/src/model/batch.dart';
import 'package:expense_tracker/src/model/journal.dart';
import 'package:expense_tracker/src/model/ledger.dart';
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
}
