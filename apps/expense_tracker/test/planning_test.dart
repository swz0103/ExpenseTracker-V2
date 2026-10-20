import 'package:expense_tracker/src/demo/seed.dart';
import 'package:expense_tracker/src/model/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("a carried budget adds only last month's leftover", () {
    final ledger = demoLedger();
    final today = ledger.today;
    ledger.setBudget('訂閱服務', 1000, carry: true);
    final budget = ledger.budgetFor('訂閱服務');
    // Set this month: nothing to carry yet.
    expect(budget.since, DateTime.utc(today.year, today.month));
    expect(ledger.allowance(budget, today.year, today.month), 1000);
    // Next month adds what this month left, never less than the limit.
    final spent = ledger.spentAgainst(budget, today.year, today.month);
    final next = DateTime.utc(today.year, today.month + 1);
    expect(
      ledger.allowance(budget, next.year, next.month),
      1000 + (spent < 1000 ? 1000 - spent : 0),
    );
    // Without carry the limit stays as set.
    ledger.setBudget('訂閱服務', 1000, carry: false);
    expect(
      ledger.allowance(ledger.budgetFor('訂閱服務'), next.year, next.month),
      1000,
    );
  });

  test('what counts against a budget follows its kind', () {
    final ledger = demoLedger();
    final today = ledger.today;
    final (year, month) = (today.year, today.month);
    expect(
      ledger.spentAgainst(Budget(Ledger.allSpending, 1), year, month),
      ledger.expense(year, month),
    );
    final byCategory = {
      for (final (c, v) in ledger.expenseByCategory(year, month)) c.name: v,
    };
    for (final MapEntry(:key, :value) in byCategory.entries) {
      expect(ledger.spentAgainst(Budget(key, 1), year, month), value);
    }
  });

  test('money comes from and goes back to the first bank account', () {
    final ledger = demoLedger();
    expect(ledger.mainAccount, 'bank');
    ledger.updateAccount(ledger.account('bank').copyWith(archived: true));
    expect(ledger.account(ledger.mainAccount).kind, isNot(AccountKind.card));
    expect(ledger.mainAccount, isNot('bank'));
  });

  test("a holding's day change follows the last close's change", () {
    final ledger = Ledger(
      today: DateTime.utc(2026, 10, 20),
      accounts: const [],
      categories: const [],
      entries: const [],
      holdings: const [
        Holding(
          '2330',
          '台積電',
          shares: 1000,
          price: 1000,
          cost: 900000,
          change: 0,
        ),
        Holding('0050', '元大台灣50', shares: 10, price: 60, cost: 500, change: 0),
      ],
      budgets: const [],
      recurring: const [],
      moves: const {'2330': -5.5},
    );
    expect(ledger.holding('2330')!.change, -5500);
    expect(ledger.holding('0050')!.change, 0);
    expect(ledger.dayChange, -5500);
  });
}

