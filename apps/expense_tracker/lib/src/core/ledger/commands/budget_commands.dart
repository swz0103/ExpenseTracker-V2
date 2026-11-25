import 'package:ledger_entries/rules.dart' show budgetIssues;

import '../cache/topic.dart';
import '../models/models.dart';
import '../persistence/write_batch.dart';
import '../repositories/budget_repository.dart';
import 'command_context.dart';
import 'command_exceptions.dart';
import 'undo.dart';

/// Writes the budgets.
final class BudgetCommands {
  BudgetCommands({
    required this._context,
    required BudgetRepository budgetRepository,
  }) : _budgets = budgetRepository;

  final CommandContext _context;
  final BudgetRepository _budgets;

  /// Sets the budget on [category]; a limit below nothing or a warning
  /// share outside 1% to 100% throws a [RecordRefused].
  void setBudget(String category, int limit, {int? warning, bool? carry}) {
    final old = _budgets.forCategory(category);
    final issues = budgetIssues(limit: limit, warning: warning ?? old.warning);
    if (issues.isNotEmpty) throw RecordRefused(issues);
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

  /// Takes away the budget on [category]; the [Undo] puts it back where
  /// it stood, as it was (D82). Null when there is none.
  Undo? removeBudget(String category) {
    final index = _budgets.all.indexWhere((b) => b.category == category);
    if (index < 0) return null;
    final removed = _budgets.all[index];
    _budgets.remove(category);
    _context.changed(const {Topic.budgets});
    _context.keep(WriteBatch(dropped: [(Collection.budget, category)]));
    return () {
      _budgets.putAt(index, removed);
      _context.changed(const {Topic.budgets});
      _context.keep(WriteBatch(budgets: [removed], putBack: true));
    };
  }
}
