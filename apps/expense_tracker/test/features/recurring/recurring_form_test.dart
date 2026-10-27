import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/recurring/model/recurring_form.dart';
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
  Ledger book() => Ledger(
    today: DateTime.utc(2026, 10, 4),
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 5000),
      Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
    ],
    categories: const [
      Category('居家', 'home', Color(0xFF5B8DB0)),
      Category('薪資', 'income', Color(0xFF5C9A83), income: true),
    ],
    entries: const [],
    holdings: const [],
    budgets: const [],
    recurring: const [],
    journal: _Nowhere(),
  );

  test('a new item needs a name and an amount', () {
    final ledger = book();
    final form = RecurringForm(ledger);
    expect(form.problem, '請輸入名稱');
    form.name = '房租';
    expect(form.problem, '請輸入金額');
    form.amount = 15000;
    expect(form.save(), isTrue);
    final item = ledger.recurring.single;
    expect((item.name, item.amount, item.category), ('房租', 15000, '居家'));
    expect(item.day, 4);
  });

  test(
    'income takes an income category; another currency clears the amount',
    () {
      final form = RecurringForm(book())
        ..amount = 300
        ..setIncome(true);
      expect(form.category, '薪資');
      form.setAccount('usd');
      expect(form.amount, 0);
      expect(form.currency, 'USD');
    },
  );

  test('payments are at least one step apart', () {
    final form = RecurringForm(book())..step(-1);
    expect(form.every, 1);
    form
      ..step(1)
      ..step(1);
    expect(form.every, 3);
    expect(form.rhythm, '每 3 個月 4 日');
  });
}
