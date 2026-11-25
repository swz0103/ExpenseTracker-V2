import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../baseline/baseline_ledger.dart';

/// D82: a budget taken away is told with 復原, which puts it back as it
/// was, where it stood.
void main() {
  Ledger book() => ledgerOf(
    today: day(2026, 10, 4),
    budgets: [
      const Budget('飲食', 5000),
      Budget('交通', 2000, warning: 90, carry: true, since: day(2026, 3, 1)),
      const Budget('#家用', 800),
    ],
  );

  test('the undo puts the budget back as it was, in its place', () {
    final l = book();
    final undo = l.budgetCommands.removeBudget('交通')!;
    expect([for (final b in l.budgets.all) b.category], ['飲食', '#家用']);
    undo();
    expect([for (final b in l.budgets.all) b.category], ['飲食', '交通', '#家用']);
    final back = l.budgets.forCategory('交通');
    expect(
      (back.limit, back.warning, back.carry, back.since),
      (2000, 90, true, day(2026, 3, 1)),
    );
  });

  test('nothing to take away gives no undo', () {
    expect(book().budgetCommands.removeBudget('娛樂'), isNull);
  });
}
