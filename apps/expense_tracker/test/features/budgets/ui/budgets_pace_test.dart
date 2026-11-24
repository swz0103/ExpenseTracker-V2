import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';
import '../../../support/seeded_book.dart' show emptyBook, startBudgets;

/// 預算管理's figures: an allowance's ring is read as 已用 and a percent,
/// and a month gone by says how much of the budget it 用了 (review 16:
/// progress semantics and percent call sites, the budget pace).
void main() {
  setUp(
    () => startBudgets = const [Budget(allSpending, 10000), Budget('飲食', 4000)],
  );
  tearDown(() => startBudgets = const []);

  // Today 2026-10-31: 3,000 on 飲食 in September, 1,000 in October.
  Ledger book() {
    final ledger = emptyBook();
    for (final (id, date, amount) in [
      ('sep', DateTime.utc(2026, 9, 12), 3000),
      ('oct', DateTime.utc(2026, 10, 3), 1000),
    ]) {
      ledger.entryCommands.add(
        Entry(
          id: id,
          date: date,
          type: EntryType.expense,
          amount: amount,
          account: 'cash',
          category: '飲食',
        ),
      );
    }
    return ledger;
  }

  List<(String?, String?)> rings(WidgetTester tester) => [
    for (final w in tester.widgetList<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    ))
      (w.semanticsLabel, w.semanticsValue),
  ];

  testWidgets('an allowance\'s ring is read as 已用 N%', (tester) async {
    await show(tester, 360, 1, height: 1200, book: book());
    await go(tester, ['更多', '預算管理']);
    // 飲食: 1,000 of 4,000 = 25%. (The total is the month's card, not a
    // ring.)
    expect(rings(tester), [('已用', '25%')]);
  });

  testWidgets('a month gone by says how much of the budget it 用了', (
    tester,
  ) async {
    await show(tester, 360, 1, height: 1200, book: book());
    await go(tester, ['更多', '預算管理', '~上個月']);
    // September: 3,000 of 10,000 = 30%.
    expect(find.text('用了 30%'), findsOneWidget);
  });
}
