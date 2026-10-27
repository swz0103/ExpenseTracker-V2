import 'package:expense_tracker/src/core/ledger/batch.dart';
import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/look/theme.dart';
import 'package:expense_tracker/src/core/ui/entry_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Batches implements Journal {
  @override
  Future<void> keep(Batch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  final day = DateTime.utc(2026, 10, 4);
  final lunch = Entry(
    id: 'lunch',
    date: day,
    type: EntryType.expense,
    amount: 1000,
    account: 'bank',
    category: '飲食',
    merchant: '好市多',
    note: '午餐',
  );
  final back = Entry(
    id: 'back',
    date: day,
    type: EntryType.income,
    amount: 300,
    account: 'bank',
    category: '飲食',
    refundOf: 'lunch',
  );

  Ledger book() => Ledger(
    today: day,
    accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
    categories: const [Category('飲食', 'food', Color(0xFF5C9A83))],
    entries: [lunch, back],
    holdings: const [],
    budgets: const [],
    recurring: const [],
    journal: _Batches(),
  );

  Future<void> show(WidgetTester tester, Ledger ledger, Entry e) =>
      tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: EntryTile(ledger: ledger, entry: e, onTap: () {}),
          ),
        ),
      );

  testWidgets('a spending partly refunded shows what is left', (tester) async {
    final ledger = book();
    await show(tester, ledger, lunch);
    expect(find.text('−700'), findsOneWidget);
    expect(find.text('已退 300'), findsOneWidget);
    // The merchant's first letter stands for the category's icon.
    expect(find.text('好'), findsOneWidget);
  });

  testWidgets('a refund reads as giving back, not as income', (tester) async {
    final ledger = book();
    await show(tester, ledger, back);
    expect(find.text('↩ 退款 · 原：午餐'), findsOneWidget);
    final amount = tester.widget<Text>(find.text('+300'));
    expect(amount.style?.color, Hue.muted);
  });

  test('a holding without a name is shown by its code once', () {
    const named = Holding(
      '2330',
      '台積電',
      shares: 1,
      price: 1,
      cost: 1,
      change: 0,
    );
    const unnamed = Holding(
      '2330',
      '2330',
      shares: 1,
      price: 1,
      cost: 1,
      change: 0,
    );
    expect(holdingLabel(named), '2330 台積電');
    expect(holdingLabel(unnamed), '2330');
  });
}
