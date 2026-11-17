import '../cache/topic.dart';
import '../models/models.dart';
import '../persistence/write_batch.dart';
import '../repositories/budget_repository.dart';
import 'command_context.dart';

/// Writes the budgets.
final class BudgetCommands {
  BudgetCommands({
    required this._context,
    required BudgetRepository budgetRepository,
  }) : _budgets = budgetRepository;

  final CommandContext _context;
  final BudgetRepository _budgets;

  void setBudget(String category, int limit, {int? warning, bool? carry}) {
    final old = _budgets.forCategory(category);
    final budget = Budget(
      category,
      limit,
      warning: warning ?? old.warning,
      carry: carry ?? old.carry,
      since:
          old.since ?? DateTime.utc(_context.today.year, _context.today.month),
    );
    _budgets.put(budget);
    _context.changed(const {Topic.budgets});
    _context.keep(WriteBatch(budgets: [budget]));
  }

  void removeBudget(String category) {
    _budgets.remove(category);
    _context.changed(const {Topic.budgets});
    _context.keep(WriteBatch(dropped: [(Collection.budget, category)]));
  }
}
