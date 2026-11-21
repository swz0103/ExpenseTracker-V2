import 'package:expense_tracker/src/core/design_system/month_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every calendar of the app: from Sunday, the months around left blank,
/// six weeks in a panel and only the month's weeks on a page.
void main() {
  Future<void> show(WidgetTester tester, {required bool sixWeeks}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // October 2026 starts on a Thursday and has 31 days: five
            // weeks.
            body: MonthGrid(
              year: 2026,
              month: 10,
              sixWeeks: sixWeeks,
              day: (d) => Text('$d', key: ValueKey(d)),
            ),
          ),
        ),
      );

  Offset at(WidgetTester tester, int d) =>
      tester.getCenter(find.byKey(ValueKey(d)));

  testWidgets('the first day falls under its weekday, the month only', (
    tester,
  ) async {
    await show(tester, sixWeeks: false);
    expect(find.text('日'), findsOneWidget);
    // Thursday, the fifth column; the 4th is the next Sunday, first.
    expect(at(tester, 1).dy, at(tester, 3).dy);
    expect(at(tester, 4).dy, greaterThan(at(tester, 3).dy));
    expect(at(tester, 4).dx, lessThan(at(tester, 1).dx));
    for (final d in [1, 15, 31]) {
      expect(find.byKey(ValueKey(d)), findsOneWidget);
    }
    expect(find.byKey(const ValueKey(32)), findsNothing);
    expect(find.byKey(const ValueKey(0)), findsNothing);
  });

  testWidgets('a panel keeps six weeks; a page the month\'s five', (
    tester,
  ) async {
    await show(tester, sixWeeks: true);
    expect(find.byType(Row), findsNWidgets(7));
    await show(tester, sixWeeks: false);
    expect(find.byType(Row), findsNWidgets(6));
  });
}
