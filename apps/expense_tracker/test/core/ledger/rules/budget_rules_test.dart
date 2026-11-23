import 'package:expense_tracker/src/core/ledger/rules/budget_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('budgetStatus', () {
    BudgetStatus of(int spent) =>
        budgetStatus(spent: spent, limit: 50000, warningPercent: 80);

    test('under the warning share is within, with what is left', () {
      // 50,000 - 39,999 = 10,001; 39,999 is under 80% (40,000).
      expect(of(39999), const BudgetWithin(10001));
    });

    test('from the warning share on it is near', () {
      // 80% of 50,000 = 40,000 exactly: 10,000 left.
      expect(of(40000), const BudgetNear(10000));
    });

    test('exactly at the limit is near, not over', () {
      expect(of(50000), const BudgetNear(0));
    });

    test('one unit over the limit is over by one', () {
      expect(of(50001), const BudgetOver(1));
    });

    test('over is decided on amounts, not a rounded percent', () {
      // 50,174 / 50,000 rounds to 100%, yet it is 174 over.
      expect(of(50174), const BudgetOver(174));
    });
  });
}
