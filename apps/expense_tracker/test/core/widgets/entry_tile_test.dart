import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/widgets/entry_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Batches implements LedgerDataSource {
  @override
  Future<void> keep(WriteBatch batch) async {}

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
    categories: [Category('飲食', 'food', 0xFF5C9A83)],
    entries: [lunch, back],
    holdings: const [],
    budgets: const [],
    recurring: const [],
    dataSource: _Batches(),
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
    expect(amount.style?.color, AppColors.muted);
  });

  test('a trade shows what reached or left the account', () {
    Entry trade(EntryType type, int amount, {int fee = 0, int tax = 0}) =>
        Entry(
          id: type.name,
          date: day,
          type: type,
          amount: amount,
          account: 'bank',
          holding: '2330',
          shares: type == EntryType.dividend ? 0 : 1000,
          fee: fee,
          tax: tax,
        );
    // A sale of 100,000 less 85 fee and 300 tax: 99,615 came in.
    expect(
      entryAmount(trade(EntryType.sell, 100000, fee: 85, tax: 300)),
      '+99,615',
    );
    // A dividend of 25,000 less the 528 premium: 24,472 came in.
    expect(entryAmount(trade(EntryType.dividend, 25000, tax: 528)), '+24,472');
    // A buy of 100,000 with an 85 fee: 100,085 left.
    expect(entryAmount(trade(EntryType.buy, 100000, fee: 85)), '−100,085');
    // A capital reduction returns its 40,000 whole.
    final reduction = Entry(
      id: 'r',
      date: day,
      type: EntryType.dividend,
      amount: 40000,
      account: 'bank',
      holding: '2330',
      shares: -500,
    );
    expect(entryAmount(reduction), '+40,000');
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
