import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/budgets/model/budget_month.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = DateTime.utc(2026, 10, 4);

Entry _spend(String id, String category, int amount, {int month = 10}) => Entry(
  id: id,
  date: DateTime.utc(2026, month, 2),
  type: EntryType.expense,
  amount: amount,
  account: 'bank',
  category: category,
);

Ledger _book(List<Entry> entries, List<Budget> budgets) => Ledger(
  today: _today,
  accounts: const [Account('bank', '銀行', AccountKind.bank, 0)],
  categories: const [],
  entries: entries,
  holdings: const [],
  budgets: budgets,
  recurring: const [],
);

void main() {
  test('a month sums its spending against the whole budget', () {
    final ledger = _book(
      [_spend('a', '飲食', 300), _spend('b', '交通', 200)],
      [Budget(allSpending, 1000)],
    );
    final month = BudgetMonth.of(ledger, (2026, 10));
    expect((month.spent, month.total), (500, 1000));
    expect(month.lines, isEmpty);
  });

  test('budgets with a limit come the most used first', () {
    final ledger = _book(
      [_spend('a', '飲食', 900), _spend('b', '交通', 100)],
      [Budget('交通', 1000), Budget('飲食', 1000), Budget('居家', 0)],
    );
    final lines = BudgetMonth.of(ledger, (2026, 10)).lines;
    expect(
      [for (final l in lines) (l.budget.category, l.spent, l.allowance)],
      [('飲食', 900, 1000), ('交通', 100, 1000)],
    );
    expect(lines.first.share, 0.9);
  });

  test('a month with no limit has a share of nothing', () {
    expect(const BudgetLine(Budget('x', 0), 50, 0).share, 0);
  });

  test('months run from the first entry to this one', () {
    final months = BudgetMonths(
      _book([_spend('old', '飲食', 1, month: 8)], const []),
    );
    expect((months.first, months.now), ((2026, 8), (2026, 10)));
    expect(months.step((2026, 10), -1), (2026, 9));
    expect(months.step((2026, 10), 1), isNull);
    expect(months.step((2026, 8), -1), isNull);
    expect(months.canGoBack((2026, 9)), isTrue);
    expect(months.canGoBack((2026, 8)), isFalse);
    expect(BudgetMonths.key((2026, 12)) + 1, BudgetMonths.key((2027, 1)));
  });

  test('a budget covers all spending, a tag or a category', () {
    expect(BudgetScope.of(allSpending), BudgetScope.all);
    expect(BudgetScope.of('#旅行'), BudgetScope.tag);
    expect(BudgetScope.of('飲食'), BudgetScope.category);
  });

  test('what counts against a budget this month follows its scope', () {
    final ledger = _book([
      _spend('a', '飲食', 300),
      Entry(
        id: 't',
        date: DateTime.utc(2026, 10, 3),
        type: EntryType.expense,
        amount: 50,
        account: 'bank',
        category: '交通',
        tags: ['旅行'],
      ),
    ], const []);
    final month = BudgetMonth.of(ledger, (2026, 10));
    expect(month.spentOn(Budget(allSpending, 1)), 350);
    expect(month.spentOn(Budget('飲食', 1)), 300);
    expect(month.spentOn(Budget('#旅行', 1)), 50);
  });
}
