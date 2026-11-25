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

  test('restore puts a budget back in its place, or the last', () {
    final before = [Budget('飲食', 100), Budget('#家用', 80), Budget('交通', 50)];
    final budgets = BudgetRepository([Budget('飲食', 100), Budget('交通', 50)]);
    budgets.restore(before, budgets.all, {'#家用'});
    expect(_of(budgets), [('飲食', 100), ('#家用', 80), ('交通', 50)]);
    final wide = [Budget('a', 1), Budget('b', 2), Budget('c', 3), before[0]];
    final short = BudgetRepository([Budget('#家用', 80)]);
    short.restore(wide, short.all, {'飲食'});
    expect(_of(short), [('#家用', 80), ('飲食', 100)]);
  });

  test('restore sets back only the budgets named, each in its place', () {
    final before = [Budget('飲食', 100), Budget('交通', 50), Budget('#家用', 80)];
    final budgets = BudgetRepository([
      Budget('交通', 70),
      Budget('#家用', 80),
      Budget('#新', 10),
      Budget('娛樂', 5),
    ]);
    final (:put, :dropped) = budgets.restore(before, budgets.all, {
      '交通',
      '#新',
      '飲食',
    });
    expect(_of(budgets), [('飲食', 100), ('交通', 50), ('#家用', 80), ('娛樂', 5)]);
    expect([for (final b in put) b.category], ['飲食', '交通']);
    expect(dropped, ['#新']);
  });

  test('R34: restore leaves a key changed since the change as it is', () {
    final before = [Budget('飲食', 100), Budget('交通', 50)];
    final budgets = BudgetRepository([Budget('交通', 70), Budget('#新', 10)]);
    final after = budgets.all;
    // Since the change: 交通 set again, #新 taken away and set again,
    // 飲食 set where the change had taken it away.
    budgets
      ..put(Budget('交通', 90))
      ..put(Budget('#新', 20))
      ..put(Budget('飲食', 30));
    final (:put, :dropped) = budgets.restore(before, after, {'交通', '#新', '飲食'});
    expect(_of(budgets), [('交通', 90), ('#新', 20), ('飲食', 30)]);
    expect(put, isEmpty);
    expect(dropped, isEmpty);
  });
}
