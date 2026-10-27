import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/trading.dart';
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

void main() {
  final day = DateTime.utc(2026, 10, 4);

  Ledger book() => Ledger(
    today: day,
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 100000),
      Account('cash', '現金', AccountKind.cash, 2000),
    ],
    categories: const [
      Category('飲食', 'food', Color(0xFF5C9A83)),
      Category('居家', 'home', Color(0xFF5B8DB0)),
    ],
    entries: const [],
    holdings: const [],
    budgets: const [],
    recurring: const [],
    journal: _Nowhere(),
  );

  test('a new expense starts on the first account, today', () {
    final form = ComposeForm(book(), type: EntryType.expense);
    expect(form.mode, ComposeMode.expense);
    expect(form.account, 'bank');
    expect(form.to, 'cash');
    expect(form.date, day);
    expect(form.amount, 0);
    expect(form.problem, isNotNull);
    form.setAmount(180);
    expect(form.sign, '−');
    expect(form.problem, isNull);
    final entry = form.build();
    expect(entry.amount, 180);
    expect(entry.account, 'bank');
    expect(entry.type, EntryType.expense);
  });

  test("a trade's amount follows shares and price, and the price the amount", () {
    final form = ComposeForm(book(), type: EntryType.buy)..holding = '2330';
    form
      ..setShares(1000)
      ..setPrice(600.5);
    expect(form.amount, 600500);
    form.setAmount(610000);
    expect(form.price, 610);
    final (fee, tax) = form.charges;
    expect(fee, brokerFee(610000, 1000));
    expect(tax, 0);
    expect(form.settlement, 610000 + fee);
    // A fee typed from the broker's slip is kept over the suggestion.
    form.tradeFee = 500;
    expect(form.settlement, 610500);
  });

  test('a split must add up to the amount', () {
    final form = ComposeForm(book(), type: EntryType.expense)
      ..setAmount(300)
      ..category = '飲食'
      ..toggleSplit()
      ..setPart(0, 200)
      ..addPart('居家');
    expect(form.parts, [('飲食', 200), ('居家', 100)]);
    expect(form.problem, isNull);
    form.setPart(1, 50);
    expect(form.problem, contains('差 50'));
    form.evenly();
    expect(form.parts, [('飲食', 150), ('居家', 150)]);
    expect(form.build().parts, hasLength(2));
  });

  test('lending needs someone to lend to', () {
    final form = ComposeForm(book(), type: EntryType.expense)
      ..setAmount(500)
      ..lend(back: false);
    expect(form.tab, ComposeMode.expense);
    expect(form.problem, '請選擇代墊對象');
  });

  test('moving to another tab keeps the receipt photo only', () {
    final form = ComposeForm(book(), type: EntryType.expense)
      ..setAmount(120)
      ..receipt = 'receipt.jpg';
    form.switchTo(ComposeMode.income);
    expect(form.amount, 0);
    expect(form.receipt, 'receipt.jpg');
    expect(form.type, EntryType.income);
  });

  test('an entry opened to change reads back the same', () {
    final ledger = book();
    final saved = Entry(
      id: 'lunch',
      date: DateTime.utc(2026, 10, 2),
      type: EntryType.expense,
      amount: 95,
      account: 'cash',
      category: '飲食',
      merchant: '便當店',
      note: '午餐',
    );
    ledger.add(saved);
    final form = ComposeForm(ledger, type: saved.type, editing: saved);
    expect(form.more, isTrue);
    final again = form.build();
    expect(again.id, 'lunch');
    expect(
      (again.amount, again.account, again.merchant, again.note),
      (95, 'cash', '便當店', '午餐'),
    );
  });
}
