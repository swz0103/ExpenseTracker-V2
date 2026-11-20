import '../cache/topic.dart';
import '../models/models.dart';
import '../persistence/write_batch.dart';
import '../persistence/unit_of_work.dart';
import '../repositories/budget_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/recurring_repository.dart';
import '../repositories/trash_repository.dart';
import 'command_context.dart';
import 'command_exceptions.dart';

/// Writes the categories: adding, changing, ordering and merging them; a
/// new name or a merge reaches every entry, budget and recurring item.
final class CategoryCommands {
  CategoryCommands({
    required this._context,
    required CategoryRepository categoryRepository,
    required EntryRepository entryRepository,
    required TrashRepository trashRepository,
    required RecurringRepository recurringRepository,
    required BudgetRepository budgetRepository,
  }) : _categories = categoryRepository,
       _entries = entryRepository,
       _trash = trashRepository,
       _recurring = recurringRepository,
       _budgets = budgetRepository;

  final CommandContext _context;
  final CategoryRepository _categories;
  final EntryRepository _entries;
  final TrashRepository _trash;
  final RecurringRepository _recurring;
  final BudgetRepository _budgets;

  /// Puts the categories of [names] in that order, as dragged on 分類;
  /// the others keep their places after them.
  void placeCategories(List<String> names) {
    final moved = _categories.place(names);
    if (moved.isEmpty) return;
    _context.changed(const {Topic.categories});
    _context.keep(WriteBatch(categories: moved));
  }

  void addCategory(Category category) {
    if (!_categories.isNameFree(category.name)) {
      _context.problem.value = const NameTaken();
      return;
    }
    category = CategoryRepository.trimmed(category);
    _categories.add(category);
    _context.changed(const {Topic.categories});
    _context.keep(WriteBatch(categories: [category]));
  }

  void _renameCategory(String from, String to) {
    if (from == to || to.isEmpty) return;
    _categories.rename(from, to);
    _moveUses(from, to);
    _budgets.rename(from, to);
    _context.changed(Topic.all);
  }

  /// Puts the entries, the deleted entries and the recurring items of
  /// category [from] in [to]: what comes back from 最近刪除 fits the book
  /// as it is now, not as it was.
  ///
  /// What changed is registered with [unit], when given.
  void _moveUses(String from, String to, [UnitOfWork? unit]) {
    Entry? moved(Entry e) =>
        e.category == from || e.parts.any((p) => p.$1 == from)
        ? e.withCategory(to, from: from)
        : null;
    // Each change is made first: `unit?.` would skip its argument too.
    final changed = [
      ..._entries.changeAll(moved),
      ..._trash.changeEntries(moved),
      ..._recurring.renameCategory(from, to),
    ];
    unit?.registerAllDirty(changed);
  }

  /// Changes a category's place, name, mark, colour or archive state; a
  /// new name reaches every entry, budget and recurring item that uses it.
  void updateCategory(String name, Category next) {
    if (_categories.all.every((c) => c.name != name)) return;
    if (!_categories.isNameFree(next.name, except: name)) {
      _context.problem.value = const NameTaken();
      return;
    }
    next = CategoryRepository.trimmed(next);
    final renamed = next.name != name;
    if (renamed) _renameCategory(name, next.name);
    // Whatever the edit built, it is still the category it was, in the
    // place it was dragged to.
    final kept = _categories.replace(renamed ? next.name : name, next)!;
    _context.changed(Topic.all);
    // Records are kept under the category's id, so a new name is one row.
    _context.keep(WriteBatch(categories: [kept]));
  }

  /// Moves everything in [from] to [into] and removes [from].
  void mergeCategory(String from, String into) {
    if (from == into) return;
    final unit = UnitOfWork();
    _moveUses(from, into, unit);
    if (_budgets.remove(from)) unit.registerDeleted(Collection.budget, from);
    final (:removed, :freed) = _categories.removeMerged(from);
    if (removed != null) unit.registerDeleted(Collection.category, removed.id);
    unit.registerAllDirty(freed);
    _context.changed(Topic.all);
    _context.keep(unit.batch);
  }
}
