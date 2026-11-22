// Work package 2.2: budgets by month, parents counting their children.
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../baseline/baseline_ledger.dart';
import 'known_defect.dart';

void main() {
  test('BUD-01: raising the limit later does not rewrite earlier months', () {
    var now = day(2026, 11, 15);
    final ledger = ledgerOf(
      today: now,
      clock: () => now,
      accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
      categories: [Category('飲食', 'food', 0xFF5C9A83)],
      entries: [
        entryOf(
          'n',
          day(2026, 11, 3),
          EntryType.expense,
          6000,
          'bank',
          category: '飲食',
        ),
      ],
    );
    // November: limit 10,000 with carry-over, 6,000 spent.
    ledger.budgetCommands.setBudget('飲食', 10000, carry: true);
    // December 10: the limit is raised to 15,000.
    now = day(2026, 12, 10);
    ledger.checkDay();
    ledger.budgetCommands.setBudget('飲食', 15000);
    final b = ledger.budgets.forCategory('飲食');
    // November keeps the 10,000 it had: 6,000 of 10,000 is 60%.
    expect(ledger.budgetService.allowance(b, 2026, 11), 10000);
    // December is 15,000 plus November's leftover, 10,000 - 6,000 = 4,000.
    expect(ledger.budgetService.allowance(b, 2026, 12), 19000);
  }, skip: knownDefect('BUD-01', '2.2'));

  test('BUD-02: a parent category budget counts its sub-categories', () {
    final ledger = ledgerOf(
      today: day(2026, 11, 15),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
      categories: [
        Category('餐飲', 'food', 0xFF5C9A83),
        Category('午餐', 'food', 0xFF5C9A83, parent: '餐飲'),
      ],
      entries: [
        entryOf(
          'l',
          day(2026, 11, 3),
          EntryType.expense,
          3000,
          'bank',
          category: '午餐',
        ),
      ],
    );
    ledger.budgetCommands.setBudget('餐飲', 8000);
    final budget = ledger.budgets.forCategory('餐飲');
    // Lunch is food: 3,000 of the 8,000.
    expect(ledger.budgetService.spentAgainst(budget, 2026, 11), 3000);
  }, skip: knownDefect('BUD-02', '2.2'));
}
