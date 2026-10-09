import 'dart:io';

import 'package:expense_tracker/src/charts/treemap.dart';
import 'package:expense_tracker/src/compose/calculator.dart';
import 'package:expense_tracker/src/demo/ledger.dart';
import 'package:expense_tracker/src/demo/seed.dart';
import 'package:expense_tracker/src/look/theme.dart';
import 'package:expense_tracker/src/pages/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Lay pages out with the app's own font, so widths match a phone.
  setUpAll(() async {
    final loader = FontLoader('NotoSansTC');
    for (final weight in ['Regular', 'Bold']) {
      final bytes = File('fonts/NotoSansTC-$weight.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
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
      expect(ledger.balance('bank'), 262871);
      expect(ledger.balance('card'), -7829);
      expect(ledger.cardDebt, 7829);
      expect(ledger.investValue, 681528);
      expect(ledger.investValue - ledger.investCost, 75678);
      expect(ledger.dayChange, 2717);
      expect(ledger.assets, 1253389);
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
    expect(ledger.balance('bank'), 262871 - 5820);
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

  test('confirming a recurring item books it once', () {
    final ledger = demoLedger();
    final netflix = ledger.upcoming.first;
    ledger.confirm(netflix);
    expect(ledger.confirmation(netflix, 2026, 10)!.amount, 390);
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
      ('財務報表', '減少 9,555'),
      ('投資與股息', '持股損益'),
      ('預算管理', '分類額度'),
      ('定期交易', '管理固定項目'),
      ('分類管理', '支出分類'),
      ('設定與資料', '匯出帳本'),
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
    await tester.tap(find.text('TWD'));
    await tester.pumpAndSettle();
    for (final key in ['1', '8', '0', '完成']) {
      await tester.tap(find.text(key).last);
      await tester.pumpAndSettle();
    }
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('−180')),
      findsOneWidget,
    );
    await tester.tap(find.text('記下支出'));
    await tester.pumpAndSettle();
    expect(find.text('已記下'), findsOneWidget);
    expect(ledger.expense(2026, 10), 17519 + 180);
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
}
