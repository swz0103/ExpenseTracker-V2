/// Where a budget stands: the one place that decides within, near its
/// warning share, or over. Over is decided on the amounts
/// ([isOver]), never on a rounded percentage: 50,174 of 50,000 is over
/// though it rounds to 100%.
///
/// Lives here until budgets have a package of their own
/// (`packages/ledger/budgets/rules/`).
library;

import 'package:core/percent/percent.dart' show isOver;

/// The state of a budget for what was [BudgetStatus] spent against it.
sealed class BudgetStatus {
  const BudgetStatus();
}

/// Under the warning share, with [left] still to spend.
final class BudgetWithin extends BudgetStatus {
  const BudgetWithin(this.left);

  final int left;

  @override
  bool operator ==(Object other) => other is BudgetWithin && other.left == left;

  @override
  int get hashCode => left.hashCode;
}

/// At or past the warning share but not over, with [left] still to spend.
final class BudgetNear extends BudgetStatus {
  const BudgetNear(this.left);

  final int left;

  @override
  bool operator ==(Object other) => other is BudgetNear && other.left == left;

  @override
  int get hashCode => left.hashCode;
}

/// Spent more than the limit, by [by] (one or more).
final class BudgetOver extends BudgetStatus {
  const BudgetOver(this.by);

  final int by;

  @override
  bool operator ==(Object other) => other is BudgetOver && other.by == by;

  @override
  int get hashCode => by.hashCode;
}

/// Where [spent] of a [limit] (above zero) stands, warning from
/// [warningPercent] of the limit on (the budget's own setting).
BudgetStatus budgetStatus({
  required int spent,
  required int limit,
  required int warningPercent,
}) {
  if (isOver(spent, limit)) return BudgetOver(spent - limit);
  final left = limit - spent;
  if (limit > 0 && spent * 100 >= limit * warningPercent) {
    return BudgetNear(left);
  }
  return BudgetWithin(left);
}
