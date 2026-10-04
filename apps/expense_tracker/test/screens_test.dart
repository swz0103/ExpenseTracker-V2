import 'package:expense_tracker/src/book.dart';
import 'package:expense_tracker/src/charts/demo_charts.dart';
import 'package:expense_tracker/src/demo_book.dart';
import 'package:expense_tracker/src/screens/home_screen.dart';
import 'package:expense_tracker/src/shell.dart';
import 'package:expense_tracker/src/theme.dart';
import 'package:expense_tracker/src/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final charts = demoCharts(2026, 10, 4);
  Book book() => demoBook(charts, 2026, 10, 4);

  test('the demo book matches the chart demo', () {
    final demo = book();
    expect(demo.monthDays, charts.days.last);
    expect(demo.monthTotal(EntryKind.income), charts.months.last.income);
    expect(demo.months, [(2026, 10), (2026, 9)]);
    final september = charts.days[charts.days.length - 2];
    final total = september.fold(0, (a, b) => a + b);
    final spent = [
      for (final date in demo.datesIn(2026, 9))
        demo.total(date, EntryKind.expense),
    ].fold(0, (a, b) => a + b);
    expect(spent, total);
  });

  test('amounts read as in the mock-ups', () {
    expect(dollars(12430), r'$ 12,430');
    expect(dollars(-8420), r'- $ 8,420');
    const lunch = Entry(
      '午餐',
      120,
      kind: EntryKind.expense,
      category: '餐飲',
      account: '現金',
    );
    expect(entryAmount(lunch), r'-$120');
    expect(percent(1, 8), '+12.5%');
    expect(signed(-5), '-5');
  });

  test('one huge day does not flatten the other bars', () {
    expect(barScale([100, 12300, 200, 0]), 280);
    expect(barScale([0, 0]), 1);
    expect(barScale([50]), 50);
  });

  Future<Book> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final demo = book();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: AppShell(book: demo, reports: const Text('報表內容')),
      ),
    );
    await tester.pumpAndSettle();
    return demo;
  }

  testWidgets('an expense recorded from home shows up at once', (tester) async {
    final demo = await show(tester);
    final before = demo.monthTotal(EntryKind.expense);
    expect(find.text(dollars(before)), findsOneWidget);

    await tester.tap(find.text('支出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('儲存'));
    await tester.pump();
    expect(find.text('請輸入金額'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '180');
    await tester.tap(find.text('儲存'));
    await tester.pump();
    expect(find.text('請選擇分類'), findsOneWidget);

    await tester.tap(find.text('餐飲'));
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(find.text('已記下'), findsOneWidget);
    expect(find.text(dollars(before + 180)), findsOneWidget);
  });

  testWidgets('a tapped bar shows its day below', (tester) async {
    await show(tester);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('房租'), findsNothing);
    const name = '_BarsPainter';
    final bars = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter.runtimeType.toString() == name,
    );
    await tester.tapAt(tester.getTopLeft(bars) + const Offset(3, 40));
    await tester.pumpAndSettle();
    expect(find.text('10/1 週四'), findsOneWidget);
    expect(find.text('房租'), findsOneWidget);
  });

  testWidgets('records filter by kind and reports open from more', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('記錄'));
    await tester.pumpAndSettle();
    expect(find.text('房租'), findsOneWidget);
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(find.text('房租'), findsNothing);
    expect(find.text('薪資'), findsOneWidget);

    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('報表'));
    await tester.pumpAndSettle();
    expect(find.text('報表內容'), findsOneWidget);
  });
}
