import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/accounts/model/reconcile.dart';
import 'package:expense_tracker/src/features/entries/model/compose_form.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing.
final class _Nowhere implements Journal {
  @override
  Future<void> keep(Batch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

/// 對帳, 常用, a merchant's last account, and the month's pace.
void main() {
  final day = DateTime.utc(2026, 10, 20);

  Entry spend(
    String id,
    int daysAgo,
    int amount, {
    String account = 'cash',
    String category = '飲食',
    String merchant = '',
  }) => Entry(
    id: id,
    date: day.subtract(Duration(days: daysAgo)),
    type: EntryType.expense,
    amount: amount,
    account: account,
    category: category,
    merchant: merchant,
  );

  Ledger book(List<Entry> entries) => Ledger(
    today: day,
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 100000),
      Account('cash', '現金', AccountKind.cash, 2000),
      Account('card', '信用卡', AccountKind.card, 0, closingDay: 25, dueDay: 10),
      Account('usd', '美元', AccountKind.bank, 10000, currency: 'USD'),
    ],
    categories: const [
      Category('飲食', 'food', Color(0xFF5C9A83)),
      Category('交通', 'car', Color(0xFF5B8DB0)),
    ],
    entries: entries,
    holdings: const [],
    budgets: const [],
    recurring: const [],
    journal: _Nowhere(),
  );

  group('對帳', () {
    test('less in the wallet than in the book is spending', () {
      final ledger = book([spend('a', 1, 300)]);
      final cash = ledger.account('cash');
      expect(shownBalance(ledger, cash), 1700);
      final entry = reconcile(ledger, cash, 1500)!;
      expect(entry.type, EntryType.expense);
      expect(entry.amount, 200);
      expect(entry.category, reconcileSpending);
      expect(entry.note, reconcileNote);
      expect(entry.date, day);
      ledger.add(entry);
      expect(ledger.balance('cash'), 1500);
      expect(reconcile(ledger, cash, 1500), isNull);
    });

    test('more in the bank than in the book is income', () {
      final ledger = book(const []);
      final entry = reconcile(ledger, ledger.account('bank'), 100250)!;
      expect(entry.type, EntryType.income);
      expect(entry.amount, 250);
      expect(entry.category, reconcileIncome);
    });

    test('a card is counted by what is owed', () {
      final ledger = book([spend('a', 1, 1000, account: 'card')]);
      final card = ledger.account('card');
      expect(shownBalance(ledger, card), 1000);
      // The bank says 1,200 is owed: 200 of spending was missed.
      final entry = reconcile(ledger, card, 1200)!;
      expect(entry.type, EntryType.expense);
      expect(entry.amount, 200);
      ledger.add(entry);
      expect(ledger.balance('card'), -1200);
    });

    test('an account in another currency is left alone', () {
      final ledger = book(const []);
      expect(reconcile(ledger, ledger.account('usd'), 5), isNull);
    });
  });

  test('常用: alike three times in 90 days, most often first', () {
    final ledger = book([
      for (var i = 0; i < 4; i++) spend('b$i', i * 3, 65 + i, merchant: '早餐店'),
      for (var i = 0; i < 3; i++)
        spend(
          'm$i',
          i * 5,
          1280,
          account: 'card',
          category: '交通',
          merchant: '捷運',
        ),
      // Twice only, and long ago: neither is usual.
      spend('x1', 2, 500, merchant: '書店'),
      spend('x2', 4, 500, merchant: '書店'),
      for (var i = 0; i < 3; i++) spend('o$i', 100 + i, 90, merchant: '舊店'),
    ]);
    final usual = ledger.usual();
    expect([for (final e in usual) e.merchant], ['早餐店', '捷運']);
    // The latest of each.
    expect(usual.first.amount, 65);
  });

  test('a merchant brings its category and account; 常用 fills the form', () {
    final ledger = book([
      spend('a', 3, 1280, account: 'card', category: '交通', merchant: '捷運'),
    ]);
    final form = ComposeForm(ledger, type: EntryType.expense);
    expect(form.account, 'bank');
    form.pickMerchant('捷運');
    expect(form.category, '交通');
    expect(form.account, 'card');

    final again = ComposeForm(ledger, type: EntryType.expense)
      ..startFrom(ledger.entries.single);
    expect(again.amount, 1280);
    expect(again.merchant, '捷運');
    expect(again.account, 'card');
    expect(again.date, day);
  });

  test('the month is heading where its pace so far takes it', () {
    final ledger = book(const []);
    // 20 of 31 days gone with 2,000 spent.
    expect(ledger.forecast(2000, 2026, 10), 3100);
    // A month gone by is what it was.
    expect(ledger.forecast(2000, 2026, 9), 2000);
  });
}
