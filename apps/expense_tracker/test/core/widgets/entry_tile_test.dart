import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
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

  testWidgets('D9: a screen reader says a refund as 退款, not 收入', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final ledger = book();
    await show(tester, ledger, back);
    expect(find.bySemanticsLabel(RegExp('退款 300 元')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('收入 300 元')), findsNothing);
    handle.dispose();
  });

  testWidgets('a refund row reads 退款，原：午餐, without its ↩ glyph', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final ledger = book();
    await show(tester, ledger, back);
    expect(find.bySemanticsLabel(RegExp('退款，原：午餐')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('↩')), findsNothing);
    handle.dispose();
  });

  test('D9: a refund reads 退款, income still reads 收入', () {
    expect(entrySpoken(back), '退款 300 元');
    final pay = Entry(
      id: 'pay',
      date: day,
      type: EntryType.income,
      amount: 300,
      account: 'bank',
      category: '薪資',
    );
    expect(entrySpoken(pay), '收入 300 元');
  });

  test('F06: shares are counted with thousands commas', () {
    final split = Entry(
      id: 'split',
      date: day,
      type: EntryType.dividend,
      amount: 0,
      account: 'bank',
      category: '股息',
      holding: '0050',
      shares: 21000,
      split: true,
    );
    final buy = Entry(
      id: 'buy',
      date: day,
      type: EntryType.buy,
      amount: 1000,
      account: 'bank',
      category: '投資',
      holding: '0050',
      shares: 1500,
    );
    final ledger = book();
    expect(entryDetail(ledger, split), '0050 · 分割 21,000 股');
    expect(entryDetail(ledger, buy), '0050 · 1,500 股 · 銀行');
  });

  testWidgets('F107: the amount is read out with its direction', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final ledger = book();
    await show(tester, ledger, lunch);
    // 1,000 spent less 300 given back: read 支出 700 元, not −700.
    expect(find.bySemanticsLabel(RegExp('支出 700 元')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('−700')), findsNothing);
    handle.dispose();
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

  group('deleteEntries: the one way an entry is deleted (D82)', () {
    /// Runs [deleteEntries] on [picked] from a button, and returns what
    /// it deleted.
    Future<List<Entry>> run(
      WidgetTester tester,
      Ledger ledger,
      List<Entry> picked,
    ) async {
      late List<Entry> removed;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    removed = deleteEntries(context, ledger, picked),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return removed;
    }

    testWidgets('one entry: named in the note, 復原 puts it back', (
      tester,
    ) async {
      final ledger = book();
      final removed = await run(tester, ledger, [back]);
      expect([for (final e in removed) e.id], ['back']);
      expect(ledger.entries.byId('back'), isNull);
      expect(find.text('已刪除「飲食」'), findsOneWidget);
      await tester.tap(find.byKey(Keys.snack('復原')));
      await tester.pump();
      expect(ledger.entries.byId('back'), isNotNull);
      expect(ledger.trash.all, isEmpty);
    });

    testWidgets('several: counted in the note', (tester) async {
      final ledger = book();
      await run(tester, ledger, [lunch, back]);
      expect(ledger.entries.all, isEmpty);
      expect(find.text('已刪除 2 筆'), findsOneWidget);
    });

    testWidgets('a booking of a recurring item: its period let go', (
      tester,
    ) async {
      final rent = Recurring(
        id: 'rent',
        name: '房租',
        amount: 500,
        day: 4,
        account: 'bank',
        category: '飲食',
        start: day,
      );
      final booked = Entry(
        id: 'r1',
        date: day,
        type: EntryType.expense,
        amount: 500,
        account: 'bank',
        category: '飲食',
        note: '房租',
        recurring: 'rent',
      );
      final ledger = Ledger(
        today: day,
        accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
        categories: [Category('飲食', 'food', 0xFF5C9A83)],
        entries: [booked],
        holdings: const [],
        budgets: const [],
        recurring: [rent],
        dataSource: _Batches(),
      );
      await run(tester, ledger, [booked]);
      expect(find.text('已刪除「房租」，這一期跳過'), findsOneWidget);
    });

    testWidgets('nothing held: nothing said', (tester) async {
      final ledger = book();
      final gone = Entry(
        id: 'gone',
        date: day,
        type: EntryType.expense,
        amount: 1,
        account: 'bank',
      );
      expect(await run(tester, ledger, [gone]), isEmpty);
      expect(find.byKey(Keys.snack('復原')), findsNothing);
    });
  });
}
