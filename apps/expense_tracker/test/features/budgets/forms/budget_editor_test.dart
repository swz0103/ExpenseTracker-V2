import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

/// D82: a budget taken away from its editor is not asked about first; the
/// note says so, and its 復原 puts the budget back as it was.
void main() {
  testWidgets('刪除額度 takes the budget away at once, with 復原', (tester) async {
    final ledger = demoLedger();
    final before = ledger.budgets.forCategory('居家生活');
    expect(before.limit, greaterThan(0));
    await show(tester, 360, 1, book: ledger);
    await go(tester, ['更多', '預算管理', '居家生活', '~刪除額度']);
    expect(find.byKey(Keys.confirm), findsNothing);
    expect(ledger.budgets.all.any((b) => b.category == '居家生活'), isFalse);
    expect(find.text('已刪除「居家生活」的額度'), findsOneWidget);
    await tester.tap(find.byKey(Keys.snack('復原')));
    await tester.pumpAndSettle();
    final back = ledger.budgets.forCategory('居家生活');
    expect(
      (back.limit, back.warning, back.carry),
      (before.limit, before.warning, before.carry),
    );
  });
}
