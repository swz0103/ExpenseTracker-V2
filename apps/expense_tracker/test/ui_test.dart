import 'dart:io';

import 'package:expense_tracker/src/charts/treemap.dart';
import 'package:expense_tracker/src/compose/calculator.dart';
import 'package:expense_tracker/src/compose/composer.dart';
import 'package:expense_tracker/src/demo/seed.dart';
import 'package:expense_tracker/src/look/theme.dart';
import 'package:expense_tracker/src/model/ledger.dart';
import 'package:expense_tracker/src/pages/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Lay pages out with the app's own font, so widths match a phone.
  setUpAll(() async {
    for (final (family, files) in const [
      ('Nunito', ['Nunito-Regular', 'Nunito-SemiBold', 'Nunito-Bold']),
      ('Huninn', ['Huninn-Regular']),
    ]) {
      final loader = FontLoader(family);
      for (final file in files) {
        final bytes = File('fonts/$file.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
  });

  group('the demo book matches the approved preview', () {
    final ledger = demoLedger();

    test('month figures', () {
      expect(ledger.income(2026, 10), 52000);
      expect(ledger.expense(2026, 10), 17519);
      expect(ledger.expense(2026, 9), 27074);
      expect(ledger.spentOn(DateTime.utc(2026, 10, 4)), 1390);
      expect(ledger.entriesOn(DateTime.utc(2026, 10, 4)).first.note, '週末點心');
    });

    test('balances and investments', () {
      expect(ledger.balance('cash'), 11990);
      expect(ledger.balance('bank'), 256871);
      expect(ledger.balance('card'), -10829);
      expect(ledger.cardDebt, 10829);
      expect(ledger.investValue, 681528);
      expect(ledger.investValue - ledger.investCost, 75678);
      expect(ledger.dayChange, 2717);
      expect(ledger.assets, 1250589);
      expect(ledger.totalDividends, 32120);
    });

    test('budgets and recurring items', () {
      expect(ledger.budgetFor(Ledger.allSpending).limit, 32000);
      expect(
        [for (final r in ledger.upcoming) r.name],
        ['Netflix', '家用網路', '瑜珈月費'],
      );
      expect(ledger.due, isEmpty);
    });

    test('four weeks of an account end on its balance', () {
      final weeks = ledger.weeklyChanges('cash');
      expect(weeks, hasLength(4));
      expect(weeks.last.$1, DateTime.utc(2026, 9, 28));
      expect(weeks.last.$2, -1390);
    });
  });

  test('trades are replayed, and an oversold trade is refused', () {
    final ledger = demoLedger();
    ledger.add(
      Entry(
        id: 'buy',
        date: ledger.today,
        type: EntryType.buy,
        amount: 5820,
        account: 'bank',
        holding: '0050',
        shares: 100,
      ),
    );
    expect(ledger.holding('0050')!.shares, 3100);
    expect(ledger.balance('bank'), 256871 - 5820);
    expect(
      () => ledger.add(
        Entry(
          id: 'sell',
          date: ledger.today,
          type: EntryType.sell,
          amount: 1000,
          account: 'bank',
          holding: '2603',
          shares: 50,
        ),
      ),
      throwsStateError,
    );
    expect(ledger.holding('2603')!.shares, 3);
    final removed = ledger.remove('buy')!;
    expect(ledger.holding('0050')!.shares, 3000);
    ledger.restore(removed);
    expect(ledger.holding('0050')!.shares, 3100);
  });

  test('splits, refunds and transfer fees count as spending', () {
    final ledger = demoLedger();
    final day = ledger.today;
    final before = ledger.expense(2026, 10);
    ledger.add(
      Entry(
        id: 'split',
        date: day,
        type: EntryType.expense,
        amount: 1000,
        account: 'cash',
        category: '飲食日常',
        parts: const [('飲食日常', 600), ('居家生活', 400)],
      ),
    );
    expect(ledger.expense(2026, 10), before + 1000);
    expect(ledger.spendingBetween(day, day)['居家生活'], 400);
    final split = ledger.byId('split')!;
    ledger.add(
      Entry(
        id: 'refund',
        date: day,
        type: EntryType.income,
        amount: 300,
        account: 'cash',
        category: '飲食日常',
        refundOf: split.id,
      ),
    );
    expect(ledger.expense(2026, 10), before + 700);
    expect(ledger.income(2026, 10), 52000);
    expect(ledger.refundable(split), 700);
    final bank = ledger.balance('bank');
    ledger.add(
      Entry(
        id: 'move',
        date: day,
        type: EntryType.transfer,
        amount: 10000,
        account: 'bank',
        category: '轉帳',
        to: 'digital',
        fee: 15,
      ),
    );
    expect(ledger.balance('bank'), bank - 10015);
    expect(ledger.expense(2026, 10), before + 715);
  });

  test('sales take the oldest lots first, and cards bill by instalment', () {
    final ledger = demoLedger();
    ledger.add(
      Entry(
        id: 'buy',
        date: ledger.today,
        type: EntryType.buy,
        amount: 6000,
        account: 'bank',
        holding: '2603',
        shares: 30,
        fee: 20,
      ),
    );
    expect(ledger.lotsOf('2603'), hasLength(2));
    expect(ledger.saleCost('2603', 3), 510);
    expect(ledger.saleCost('2603', 33), 510 + 6020);
    final card = ledger.account('card');
    final phone = ledger.instalmentsOn(card).single;
    expect(phone.note, 'iPhone 17');
    expect(ledger.billedPeriods(phone, ledger.today), 3);
    expect(ledger.billed(phone, ledger.today), 9000);
  });

  test('confirming a recurring item books it once', () {
    final ledger = demoLedger();
    final netflix = ledger.upcoming.first;
    ledger.confirm(netflix);
    final booked = [
      for (final e in ledger.entriesIn(2026, 10))
        if (e.recurring == netflix.id) e.amount,
    ];
    expect(booked, [390]);
    expect([for (final r in ledger.upcoming) r.id], ['internet', 'yoga']);
  });

  test('the calculator and the treemap', () {
    expect(evaluate('12+3×4−5÷2'), 21.5);
    expect(evaluate('7×'), isNull);
    expect(evaluate(''), 0);
    const box = Rect.fromLTWH(0, 0, 100, 100);
    final rects = treemapLayout([600, 300, 100], box);
    expect(rects[0].width * rects[0].height, closeTo(6000, 0.01));
    expect(rects[2].width * rects[2].height, closeTo(1000, 0.01));
  });

  Future<Ledger> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ledger = demoLedger();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: AppShell(ledger: ledger),
      ),
    );
    await tester.pumpAndSettle();
    return ledger;
  }

  testWidgets('every place opens', (tester) async {
    await show(tester);
    expect(find.text('總覽'), findsWidgets);
    expect(find.text('17,519'), findsOneWidget);
    await tester.tap(find.text('紀錄'));
    await tester.pumpAndSettle();
    expect(find.text('收支紀錄'), findsOneWidget);
    await tester.tap(find.text('帳戶'));
    await tester.pumpAndSettle();
    expect(find.text('我的帳戶'), findsOneWidget);
    await tester.tap(find.text('日常銀行'));
    await tester.pumpAndSettle();
    expect(find.text('近四週'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    for (final (tool, mark) in const [
      ('財務報表', '收支與淨資產'),
      ('投資與股息', 'ETF'),
      ('預算管理', '分類與標籤額度'),
      ('定期交易', '管理固定項目'),
      ('分類管理', '支出分類'),
      ('設定與資料', '匯出全部'),
    ]) {
      await tester.tap(find.text(tool));
      await tester.pumpAndSettle();
      expect(find.text(mark), findsOneWidget, reason: tool);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('an expense is recorded with the calculator', (tester) async {
    final ledger = await show(tester);
    await tester.tap(find.byTooltip('記一筆'));
    await tester.pumpAndSettle();
    expect(find.text('新增支出'), findsOneWidget);
    await tester.tap(find.text('記下支出'));
    await tester.pump();
    expect(find.text('請輸入金額'), findsOneWidget);
    await tester.tap(find.text('金額'));
    await tester.pumpAndSettle();
    for (final key in ['1', '8', '0', '完成']) {
      await tester.tap(find.text(key).last);
      await tester.pumpAndSettle();
    }
    expect(
      find.descendant(of: find.byType(Composer), matching: find.text('−180')),
      findsOneWidget,
    );
    await tester.tap(find.text('記下支出'));
    await tester.pumpAndSettle();
    expect(find.text('已記下'), findsOneWidget);
    expect(ledger.expense(2026, 10), 17519 + 180);
  });

  testWidgets('lending sits under expense and repayment under income', (
    tester,
  ) async {
    final ledger = await show(tester);
    Finder inSheet(String text) =>
        find.descendant(of: find.byType(Composer), matching: find.text(text));
    Future<void> type(String label, List<String> keys) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      for (final key in [...keys, '完成']) {
        await tester.tap(find.text(key).last);
        await tester.pumpAndSettle();
      }
    }

    await tester.tap(find.byTooltip('記一筆'));
    await tester.pumpAndSettle();
    expect(inSheet('代墊'), findsOneWidget);
    await tester.tap(inSheet('代墊'));
    await tester.pumpAndSettle();
    expect(inSheet('幫誰付'), findsOneWidget);
    expect(inSheet('代墊朋友'), findsOneWidget);
    await type('代墊金額', ['5', '0', '0']);
    await tester.tap(find.text('記下代墊'));
    await tester.pumpAndSettle();
    expect(ledger.balance('lent'), 3200 + 500);
    expect(ledger.expense(2026, 10), 17519);

    await tester.tap(find.byTooltip('記一筆'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('收入'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('對方還錢'));
    await tester.pumpAndSettle();
    expect(inSheet('誰還錢'), findsOneWidget);
    await type('還款金額', ['3', '0', '0']);
    await tester.tap(find.text('記下還款'));
    await tester.pumpAndSettle();
    expect(ledger.balance('lent'), 3700 - 300);
    expect(ledger.income(2026, 10), 52000);
  });

  testWidgets('a deleted entry can be restored', (tester) async {
    final ledger = await show(tester);
    await tester.tap(find.text('紀錄'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('週末點心'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除').last);
    await tester.pumpAndSettle();
    expect(ledger.expense(2026, 10), 17519 - 200);
    await tester.tap(find.text('復原'));
    await tester.pumpAndSettle();
    expect(ledger.expense(2026, 10), 17519);
  });

  testWidgets('picked entries are deleted at once and come back', (
    tester,
  ) async {
    final ledger = await show(tester);
    await tester.tap(find.text('紀錄'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('週末點心'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已選 1 筆'), findsOneWidget);
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();
    expect(ledger.expense(2026, 10), 17519 - 200);
    expect(ledger.trash.single.entry.note, '週末點心');
    await tester.tap(find.text('復原'));
    await tester.pumpAndSettle();
    expect(ledger.expense(2026, 10), 17519);
    expect(ledger.trash, isEmpty);
  });
}
