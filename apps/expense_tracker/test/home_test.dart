import 'package:expense_tracker/src/charts/demo_charts.dart';
import 'package:expense_tracker/src/home/category_section.dart';
import 'package:expense_tracker/src/home/day_section.dart';
import 'package:expense_tracker/src/home/holdings_section.dart';
import 'package:expense_tracker/src/home/home_demo.dart';
import 'package:expense_tracker/src/home/home_page.dart';
import 'package:expense_tracker/src/home/month_section.dart';
import 'package:expense_tracker/src/shell.dart';
import 'package:expense_tracker/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int total(Iterable<int> values) => values.fold(0, (a, b) => a + b);

Finder painted(String name) => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint && widget.painter.runtimeType.toString() == name,
);

void main() {
  final charts = demoCharts(2026, 10, 4);
  final data = demoHome(charts, 2026, 10, 4);

  test('the home demo matches the chart demo', () {
    expect(data.week, hasLength(7));
    expect(data.week.first.date, DateTime.utc(2026, 9, 28));
    expect(data.week.last.date, DateTime.utc(2026, 10, 4));
    for (final day in data.week) {
      final month = charts.days[day.date.month == 10 ? 11 : 10];
      expect(day.spent, month[day.date.day - 1]);
    }
    expect(total(data.days), data.month.expense);
    expect(data.daysInMonth, 31);
  });

  test('strip pieces keep order and fit', () {
    final pieces = stripPieces([500, 300, 0, 200], 300);
    expect(pieces, hasLength(4));
    expect(pieces.first.$1, 0);
    expect(pieces.last.$2, closeTo(300, 0.001));
    for (var i = 1; i < pieces.length; i++) {
      expect(pieces[i].$1, greaterThan(pieces[i - 1].$2));
    }
    expect(pieces[2].$2 - pieces[2].$1, closeTo(3, 0.001));
  });

  test('gains read with a sign', () {
    expect(signed(1200), '+1,200');
    expect(signed(-5), '-5');
    expect(percent(1, 8), '+12.5%');
  });

  test('the month-end estimate does not repeat rent', () {
    expect(monthEstimate([12500, 300, 500, 400], 30), 13700 + 500 * 26);
    expect(monthEstimate([], 30), 0);
  });

  test('one huge day does not shrink the rest of the week', () {
    expect(weekScale([100, 12300, 200, 0]), 400);
    expect(weekScale([0, 0]), 1);
    expect(weekScale([50]), 50);
  });

  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('home cards open when tapped', (tester) async {
    await show(tester, HomePage(data: data));
    expect(find.text('月底預估'), findsNothing);
    await tester.tap(find.text('10月支出'));
    await tester.pumpAndSettle();
    expect(find.text('月底預估'), findsOneWidget);

    final strip = painted('_StripPainter');
    await tester.tapAt(tester.getTopLeft(strip) + const Offset(5, 10));
    await tester.pumpAndSettle();
    expect(find.textContaining('上月'), findsOneWidget);

    expect(find.text('2330'), findsNothing);
    await tester.tap(find.text('投資'));
    await tester.pumpAndSettle();
    expect(find.text('2330'), findsOneWidget);

    expect(find.text('10月4日 週日'), findsOneWidget);
    final week = painted('_WeekPainter');
    await tester.tapAt(tester.getTopLeft(week) + const Offset(10, 20));
    await tester.pumpAndSettle();
    expect(find.text('9月28日 週一'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shell switches places', (tester) async {
    await show(
      tester,
      AppShell(
        title: '今天',
        home: const Text('首頁內容'),
        reports: const Text('報表內容'),
      ),
    );
    expect(find.text('首頁內容'), findsOneWidget);
    await tester.tap(find.text('明細'));
    await tester.pumpAndSettle();
    expect(find.text('明細畫面製作中'), findsOneWidget);
    await tester.tap(find.text('報表'));
    await tester.pumpAndSettle();
    expect(find.text('報表內容'), findsOneWidget);
    await tester.tap(find.byTooltip('記一筆'));
    await tester.pump();
    expect(find.text('「記一筆」還在製作中'), findsOneWidget);
  });
}
