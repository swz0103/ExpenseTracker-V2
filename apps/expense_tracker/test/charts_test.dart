import 'package:expense_tracker/src/charts/bars_chart.dart';
import 'package:expense_tracker/src/charts/calendar_chart.dart';
import 'package:expense_tracker/src/charts/chart_data.dart';
import 'package:expense_tracker/src/charts/chart_gallery.dart';
import 'package:expense_tracker/src/charts/demo_charts.dart';
import 'package:expense_tracker/src/charts/donut_chart.dart';
import 'package:expense_tracker/src/charts/treemap_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int total(Iterable<int> values) => values.fold(0, (a, b) => a + b);

/// The canvas a chart paints with the private painter [name].
Finder painted(String name) => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint && widget.painter.runtimeType.toString() == name,
);

void main() {
  final data = demoCharts(2026, 10, 3);

  test('the demo data adds up', () {
    expect(data.months, hasLength(12));
    expect(data.months.first.month, 11);
    expect(data.months.last.month, 10);
    for (final (i, month) in data.months.indexed) {
      final slices = data.categories[i];
      expect(total(slices.map((s) => s.amount)), month.expense);
      for (final slice in slices) {
        expect(total(slice.children.map((c) => c.amount)), slice.amount);
      }
      expect(total(data.days[i]), month.expense);
    }
    expect(data.days.last, hasLength(3));
    expect(data.days[10], hasLength(30));
    final again = demoCharts(2026, 10, 3);
    expect(again.months.last.expense, data.months.last.expense);
  });

  test('labels and grid steps are round', () {
    expect(groupDigits(1234567), '1,234,567');
    expect(groupDigits(-950), '-950');
    expect(compactAmount(8500), '8.5千');
    expect(compactAmount(120000), '12萬');
    expect(compactAmount(640), '640');
    expect(gridStep(130000, 3), 50000);
    expect(gridStep(29000, 3), 10000);
    expect(gridStep(0, 3), 1);
  });

  test('treemap tiles fill the box in proportion', () {
    const bounds = Rect.fromLTWH(0, 0, 300, 200);
    final values = [500, 250, 150, 60, 40];
    final rects = treemapLayout(values, bounds);
    expect(rects, hasLength(values.length));
    final area = bounds.width * bounds.height;
    for (final (i, rect) in rects.indexed) {
      expect(bounds.inflate(0.001).contains(rect.topLeft), isTrue);
      expect(bounds.inflate(0.001).contains(rect.bottomRight), isTrue);
      final expected = area * values[i] / total(values);
      expect(rect.width * rect.height, closeTo(expected, 0.01));
    }
    expect(treemapLayout([0, 0], bounds), [Rect.zero, Rect.zero]);
  });

  test('donut taps find the slice under them', () {
    final slices = [
      const CategorySlice('a', 50, Colors.red),
      const CategorySlice('b', 25, Colors.blue),
      const CategorySlice('c', 25, Colors.green),
    ];
    const size = Size(200, 200);
    // Slices run clockwise from twelve o'clock; the ring runs 53 to 98
    // from the centre.
    expect(donutSliceAt(slices, size, const Offset(170, 90)), 0);
    expect(donutSliceAt(slices, size, const Offset(60, 170)), 1);
    expect(donutSliceAt(slices, size, const Offset(30, 90)), 2);
    expect(donutSliceAt(slices, size, const Offset(100, 100)), isNull);
  });

  test('calendar cells start on Sunday', () {
    final october = CalendarLayout(2026, 10);
    expect(october.offset, 4);
    expect(october.rows, 5);
    final first = october.cell(1, 350);
    expect(october.dayAt(first.center, 350), 1);
    expect(october.dayAt(const Offset(10, 30), 350), isNull);
    expect(calendarShade(0, [10, 20]), 0);
    expect(calendarShade(20, [10, 20, 400]), lessThan(4));
    expect(calendarShade(400, [10, 20, 400]), 4);
  });

  Future<void> show(WidgetTester tester, Widget chart) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ListView(children: [chart])),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a bar shows that month', (tester) async {
    await show(tester, BarsChart(data: data));
    expect(find.text('2026年10月'), findsOneWidget);
    final chart = painted('_BarsPainter');
    await tester.tapAt(tester.getTopLeft(chart) + const Offset(5, 50));
    await tester.pump();
    expect(find.text('2025年11月'), findsOneWidget);
  });

  testWidgets('tapping a calendar day shows it', (tester) async {
    await show(tester, CalendarChart(data: data));
    expect(find.textContaining('10月3日'), findsOneWidget);
    final chart = painted('_CalendarPainter');
    final layout = CalendarLayout(2026, 10);
    final width = tester.getSize(chart).width;
    final day = layout.cell(2, width).center;
    await tester.tapAt(tester.getTopLeft(chart) + day);
    await tester.pump();
    expect(find.textContaining('10月2日'), findsOneWidget);
  });

  testWidgets('a treemap category opens its subcategories', (tester) async {
    await show(tester, TreemapChart(data: data));
    expect(find.text('全部'), findsOneWidget);
    final chart = painted('_TreemapPainter');
    await tester.tapAt(tester.getTopLeft(chart) + const Offset(10, 10));
    await tester.pumpAndSettle();
    final largest = data.categories.last.first.name;
    expect(find.text(largest), findsOneWidget);
  });

  testWidgets('every gallery tab opens', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChartGallery(data: data)));
    for (final name in ['B 趨勢', 'C 圓環', 'D 日曆', 'E 方塊', 'A 長條']) {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the donut lifts a tapped category', (tester) async {
    await show(tester, DonutChart(data: data));
    await tester.tap(find.text('居家'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
