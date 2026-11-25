import 'package:core/foundation_values.dart' show YearMonth;

import '../../../core/ledger/ledger.dart';

/// What a budget covers: all spending, a tag's, or a category's.
enum BudgetScope {
  all,
  tag,
  category;

  /// The scope of the budget named [name]: [allSpending], `#` and a tag,
  /// or a category.
  static BudgetScope of(String name) => name == allSpending
      ? all
      : name.startsWith('#')
      ? tag
      : category;
}

/// One budget in a month: what counts against it and what it allows.
final class BudgetLine {
  const BudgetLine(this.budget, this.spent, this.allowance);

  final Budget budget;
  final int spent;

  /// The limit for the month, with what was carried in.
  final int allowance;

  /// The share used; 0 for a budget that allows nothing.
  double get share => allowance == 0 ? 0 : spent / allowance;

  /// Within, near its warning share, or over.
  BudgetStatus get status => budgetStatus(
    spent: spent,
    limit: allowance,
    warningPercent: budget.warning,
  );
}

/// What 預算管理 shows for one month: all spending against the whole
/// budget, and each category's and tag's budget, the most used first.
final class BudgetMonth {
  BudgetMonth.of(
    this.month, {
    required this._reports,
    required this._budgets,
    required this._service,
  });

  final ReportService _reports;
  final BudgetReader _budgets;
  final BudgetService _service;
  final YearMonth month;

  int get _year => month.year;
  int get _month => month.month;

  /// All spending of the month.
  late final int spent = _reports.expense(_year, _month);

  /// The budget for all spending; a limit of 0 when none is set.
  Budget get whole => _budgets.forCategory(allSpending);

  /// What the whole budget allows this month.
  late final int total = _service.allowance(whole, _year, _month);

  /// Where all spending stands against [total]: within, near the whole
  /// budget's warning share, or over.
  BudgetStatus get status =>
      budgetStatus(spent: spent, limit: total, warningPercent: whole.warning);

  /// What counts against [budget] this month.
  int spentOn(Budget budget) =>
      BudgetScope.of(budget.category) == BudgetScope.all
      ? spent
      : _service.spentAgainst(budget, _year, _month);

  /// Each category's and tag's budget with a limit, overspent first,
  /// then by the share used.
  late final List<BudgetLine> lines = [
    for (final b in _budgets.all)
      if (b.category != allSpending && b.limit > 0)
        BudgetLine(
          b,
          _service.spentAgainst(b, _year, _month),
          _service.allowance(b, _year, _month),
        ),
  ]..sort((a, b) => b.share.compareTo(a.share));
}

/// The months 預算管理 can show: from the book's first to this one.
final class BudgetMonths {
  BudgetMonths(this._reports, {required this._today});

  final ReportService _reports;

  /// The ledger's clock: a page kept open past midnight moves on with it.
  final DateTime Function() _today;

  /// This month.
  YearMonth get now => YearMonth.of(_today());

  /// The month of the book's first entry.
  YearMonth get first {
    return YearMonth.of(_reports.firstDay);
  }

  /// Whether a month before [month] can be shown.
  bool canGoBack(YearMonth month) => month.compareTo(first) > 0;

  /// Whether [month] is from the first month to this one.
  bool covers(YearMonth month) =>
      month.compareTo(first) >= 0 && month.compareTo(now) <= 0;

  /// [by] months on from [month]; null past this month or before the
  /// first.
  YearMonth? step(YearMonth month, int by) {
    final next = month.addMonths(by);
    return covers(next) ? next : null;
  }
}
