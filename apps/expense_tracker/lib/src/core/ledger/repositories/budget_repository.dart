import '../models/models.dart';

/// What the screens and queries may ask of the budgets.
abstract interface class BudgetReader {
  /// Every budget, in the order set; the list cannot be changed.
  List<Budget> get all;

  /// The budget for [category]: a category's name, a `#` and a tag, or
  /// the name of all spending. A budget of nothing when none is set.
  Budget forCategory(String category);
}

/// The budgets of the book, one for each category, tag or the total.
/// The commands that write use it; the screens see a [BudgetReader].
final class BudgetRepository implements BudgetReader {
  BudgetRepository([Iterable<Budget> budgets = const []])
    : _items = [...budgets];

  final List<Budget> _items;

  @override
  List<Budget> get all => List.unmodifiable(_items);

  @override
  Budget forCategory(String category) => _items.firstWhere(
    (b) => b.category == category,
    orElse: () => Budget(category, 0),
  );

  /// Puts [budget] in place of the one for what it covers, at the end.
  void put(Budget budget) {
    remove(budget.category);
    _items.add(budget);
  }

  /// Takes away the budget for [category]; nothing when there is none.
  bool remove(String category) {
    final count = _items.length;
    _items.removeWhere((b) => b.category == category);
    return _items.length != count;
  }

  /// Gives the budget for [from] to [to], as when a category or a tag is
  /// renamed (a tag as `#` and its name). When [to] already had one, the
  /// one set first is kept: there is one budget for each.
  ///
  /// Returns whether [from] had a budget, and the budget now under [to]
  /// that came from it: null when [from] had none or [to] kept its own.
  ({bool removed, Budget? moved}) rename(String from, String to) {
    if (from == to) return (removed: false, moved: null);
    final index = _items.indexWhere((b) => b.category == from);
    if (index < 0) return (removed: false, moved: null);
    final renamed = _items[index].renamed(to);
    _items[index] = renamed;
    final seen = <String>{};
    _items.retainWhere((b) => seen.add(b.category));
    return (
      removed: true,
      moved: _items.any((b) => identical(b, renamed)) ? renamed : null,
    );
  }

  /// Takes the budgets of [budgets], as when the book is read again.
  void replaceWith(Iterable<Budget> budgets) {
    final copy = [...budgets];
    _items
      ..clear()
      ..addAll(copy);
  }
}
