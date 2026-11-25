import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/repositories/budget_repository.dart';
import 'package:flutter_test/flutter_test.dart';

List<(String, int)> _of(BudgetRepository r) => [
  for (final b in r.all) (b.category, b.limit),
];

void main() {
  test('a category with no budget has a budget of nothing', () {
    final budgets = BudgetRepository();
    final none = budgets.forCategory('飲食');
    expect((none.category, none.limit), ('飲食', 0));
    expect(budgets.all, isEmpty);
  });

  test('a budget set again takes the place of the old one, at the end', () {
    final budgets = BudgetRepository([Budget('飲食', 100), Budget('交通', 50)]);
    budgets.put(Budget('飲食', 300));
    expect(_of(budgets), [('交通', 50), ('飲食', 300)]);
    expect(budgets.forCategory('飲食').limit, 300);
  });

  test('a budget taken away is gone; one never set changes nothing', () {
    final budgets = BudgetRepository([Budget('飲食', 100), Budget('#家用', 80)]);
    budgets.remove('#家用');
    budgets.remove('不存在');
    expect(_of(budgets), [('飲食', 100)]);
  });

  test('renaming moves the budget to the new name, keeping what it holds', () {
    final budgets = BudgetRepository([
      Budget('飲食', 100, warning: 70, carry: true),
    ]);
    budgets.rename('飲食', '吃飯');
    final moved = budgets.forCategory('吃飯');
    expect((moved.limit, moved.warning, moved.carry), (100, 70, true));
    expect(budgets.forCategory('飲食').limit, 0);
  });

  test('renaming onto a name with a budget keeps the one set first', () {
    final budgets = BudgetRepository([Budget('#旅行', 500), Budget('#出遊', 900)]);
    budgets.rename('#出遊', '#旅行');
    expect(_of(budgets), [('#旅行', 500)]);
  });

  test('renaming what has no budget changes nothing', () {
    final budgets = BudgetRepository([Budget('飲食', 100)]);
    budgets.rename('交通', '通勤');
    expect(_of(budgets), [('飲食', 100)]);
  });

  test('the list handed out cannot be changed and is not the store', () {
    final given = [Budget('飲食', 100)];
    final budgets = BudgetRepository(given);
    given.add(Budget('交通', 1));
    expect(budgets.all, hasLength(1));
    expect(() => budgets.all.add(Budget('x', 1)), throwsUnsupportedError);
  });

  test('the budgets of a book read again take the place of all of them', () {
    final budgets = BudgetRepository([Budget('飲食', 100)]);
    budgets.replaceWith([Budget('交通', 50), Budget('#家用', 80)]);
    expect(_of(budgets), [('交通', 50), ('#家用', 80)]);
    // Replacing with its own list is safe.
    budgets.replaceWith(budgets.all);
    expect(_of(budgets), [('交通', 50), ('#家用', 80)]);
  });

  test('a budget put back takes its place again, or the last', () {
    final budgets = BudgetRepository([Budget('飲食', 100), Budget('交通', 50)]);
    budgets.putAt(1, Budget('#家用', 80));
    expect(_of(budgets), [('飲食', 100), ('#家用', 80), ('交通', 50)]);
    budgets.putAt(9, Budget('飲食', 70));
    expect(_of(budgets), [('#家用', 80), ('交通', 50), ('飲食', 70)]);
  });
}
