import 'package:expense_tracker/src/core/ledger/batch.dart';
import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing: only counts the batches it was handed.
final class _Batches implements Journal {
  var kept = 0;

  @override
  Future<void> keep(Batch batch) async => kept++;

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  final day = DateTime.utc(2026, 10, 4);

  Ledger book() => Ledger(
    today: day,
    accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
    categories: const [Category('飲食', 'food', Color(0xFF5C9A83))],
    entries: [
      Entry(
        id: 'lunch',
        date: day,
        type: EntryType.expense,
        amount: 120,
        account: 'bank',
        category: '飲食',
        merchant: '便當店',
      ),
    ],
    holdings: const [],
    budgets: const [],
    recurring: const [],
    journal: _Batches(),
  );

  Entry spend(String id) => Entry(
    id: id,
    date: day,
    type: EntryType.expense,
    amount: 80,
    account: 'bank',
    category: '飲食',
    merchant: '飲料店',
  );

  test('a budget change keeps what rests on entries only', () async {
    final ledger = book();
    final merchants = ledger.merchants;
    final entriesBefore = ledger.revisionOf(Area.entries);
    ledger.setBudget('飲食', 5000);
    expect(ledger.revisionOf(Area.budgets), 1);
    expect(ledger.revisionOf(Area.entries), entriesBefore);
    expect(identical(ledger.merchants, merchants), isTrue);

    ledger.add(spend('tea'));
    expect(ledger.revisionOf(Area.entries), entriesBefore + 1);
    expect(identical(ledger.merchants, merchants), isFalse);
    expect(ledger.merchants, containsAll(['便當店', '飲料店']));
    await ledger.settled;
  });

  test('a page watching some areas hears only of those', () async {
    final ledger = book();
    var budgets = 0;
    var market = 0;
    var all = 0;
    ledger.watch(const {Area.budgets}).addListener(() => budgets++);
    ledger.watch(const {Area.market}).addListener(() => market++);
    ledger.addListener(() => all++);

    ledger.setBudget('飲食', 5000);
    expect((budgets, market, all), (1, 0, 1));

    ledger.add(spend('tea'));
    expect((budgets, market, all), (1, 0, 2));
    await ledger.settled;
  });
}
