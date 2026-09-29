import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:reports/reports.dart';

/// A monthly, single-currency expense limit. Empty account/tag sets mean all;
/// within a set selection is OR, while the dimensions combine with AND.
final class BudgetPlan {
  BudgetPlan({
    required this.id,
    required this.workspace,
    required this.month,
    required this.limit,
    this.version = 1,
    this.categoryId,
    Set<PublicId> accountIds = const {},
    Set<PublicId> tagIds = const {},
    this.warningPercent = 80,
  }) : accountIds = Set.unmodifiable(accountIds),
       tagIds = Set.unmodifiable(tagIds) {
    if (version < 1 ||
        limit.minorUnits <= BigInt.zero ||
        warningPercent < 1 ||
        warningPercent > 100) {
      throw const FormatException('Invalid budget limit or warning level');
    }
  }

  final PublicId id;
  final WorkspaceId workspace;
  final ReportMonth month;
  final Money limit;
  final int version;
  final PublicId? categoryId;
  final Set<PublicId> accountIds;
  final Set<PublicId> tagIds;
  final int warningPercent;
}

/// The same classified report effect used by monthly reports, with its saved
/// workspace. Callers must load effective Ledger facts, not
/// raw legs, to avoid treating transfers or card payments as new spending.
final class BudgetFact {
  const BudgetFact({required this.workspace, required this.report});

  final WorkspaceId workspace;
  final MonthlyFact report;
}

final class BudgetResult {
  const BudgetResult({
    required this.plan,
    required this.spent,
    required this.remaining,
    required this.atWarning,
    required this.overLimit,
    required this.otherCurrencyFacts,
  });

  final BudgetPlan plan;

  /// Signed net consumption. Refunds and reversals may make it negative.
  final Money spent;
  final Money remaining;
  final bool atWarning;
  final bool overLimit;

  /// Matching foreign-currency effects excluded because no FX quote was given.
  final int otherCurrencyFacts;
}

/// Deterministic read model. No balance mutation, projection cache, or FX guess.
BudgetResult evaluateBudget(
  BudgetPlan plan,
  Iterable<BudgetFact> source, {
  required CategoryCatalog categories,
}) {
  if (categories.workspace != plan.workspace) {
    throw const FormatException('Budget category workspace mismatch');
  }
  final selected = plan.categoryId == null
      ? null
      : categories.get(plan.categoryId!);
  if (selected != null && selected.kind != CategoryKind.expense) {
    throw const FormatException('Budget category must be an expense');
  }
  final seen = <PublicId>{};
  var spent = BigInt.zero;
  var foreign = 0;
  for (final fact in source) {
    final row = fact.report;
    if (fact.workspace != plan.workspace ||
        row.date.year != plan.month.year ||
        row.date.month != plan.month.month ||
        !seen.add(row.id)) {
      throw const FormatException('Invalid budget facts');
    }
    if (plan.accountIds.isNotEmpty &&
        !plan.accountIds.contains(row.accountId)) {
      continue;
    }
    if (plan.tagIds.isNotEmpty && !row.tagIds.any(plan.tagIds.contains)) {
      continue;
    }
    final units = selected == null
        ? row.expense.minorUnits
        : _categoryExpense(row, selected, categories);
    if (units == BigInt.zero) continue;
    if (row.currency != plan.limit.currency) {
      foreign++;
      continue;
    }
    spent += units;
  }
  final consumed = Money(plan.limit.currency, spent);
  final remaining = Money(plan.limit.currency, plan.limit.minorUnits - spent);
  return BudgetResult(
    plan: plan,
    spent: consumed,
    remaining: remaining,
    atWarning:
        spent * BigInt.from(100) >=
        plan.limit.minorUnits * BigInt.from(plan.warningPercent),
    overLimit: spent > plan.limit.minorUnits,
    otherCurrencyFacts: foreign,
  );
}

BigInt _categoryExpense(
  MonthlyFact row,
  Category selected,
  CategoryCatalog catalog,
) {
  if (row.expense.minorUnits == BigInt.zero) return BigInt.zero;
  var magnitude = BigInt.zero;
  for (final allocation in row.allocations) {
    final category = catalog.get(allocation.categoryId);
    if (category.id == selected.id || category.parentId == selected.id) {
      magnitude += allocation.amount.minorUnits;
    }
  }
  return row.expense.minorUnits.isNegative ? -magnitude : magnitude;
}
