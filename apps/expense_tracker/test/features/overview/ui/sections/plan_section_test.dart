import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/places.dart';

/// 總覽's budget card (review 16: 本月超支 with the amount over).
void main() {
  setUpAll(loadFonts);

  testWidgets('a whole budget spent past reads 本月超支 and how much over', (
    tester,
  ) async {
    final ledger = demoLedger();
    // 2026-10-04: what October has spent so far, against a budget of 1.
    final spent = ledger.reportService.expense(2026, 10);
    expect(spent, greaterThan(1));
    ledger.budgetCommands.setBudget(allSpending, 1);
    await show(tester, 360, 1, book: ledger);
    expect(find.text('本月超支'), findsOneWidget);
    expect(find.text('本月剩'), findsNothing);
  });

  testWidgets('a whole budget not reached reads 本月剩', (tester) async {
    final ledger = demoLedger();
    ledger.budgetCommands.setBudget(allSpending, 100000000);
    await show(tester, 360, 1, book: ledger);
    expect(find.text('本月剩'), findsOneWidget);
    expect(find.text('本月超支'), findsNothing);
  });
}
