import '../models/models.dart';
import '../repositories/entry_repository.dart';
import '../services/report_service.dart';

/// What has been spent against a budget, and where a month is heading.
final class BudgetService {
  BudgetService({
    required this._entries,
    required ReportService reportService,
    required this._today,
  }) : _reports = reportService;

  final EntryReader _entries;
  final ReportService _reports;
  final DateTime Function() _today;

  /// The days of [year]/[month] gone by, today included, and all its
  /// days; every day of a month other than this one.
  (int, int) daysGone(int year, int month) {
    final days = DateTime.utc(year, month + 1, 0).day;
    final current = year == _today().year && month == _today().month;
    return (current ? _today().day : days, days);
  }

  /// What spending carrying [tag] came to in [year]/[month].
  int spentOnTag(String tag, int year, int month) {
    var total = 0;
    for (final e in _entries.inMonth(year, month)) {
      if (e.tags.contains(tag)) total += e.spending;
    }
    return total;
  }

  /// Where [spent] in [year]/[month] is heading by the month's end at the
  /// pace so far: the month's spending for a month gone by.
  int forecast(int spent, int year, int month) {
    final (passed, days) = daysGone(year, month);
    if (passed >= days || passed == 0) return spent;
    return (spent * days / passed).round();
  }

  /// What counts against [budget] in [year]/[month]: all spending, the
  /// spending carrying its tag, or its category's share of spending.
  int spentAgainst(Budget budget, int year, int month) {
    if (budget.category == allSpending) return _reports.expense(year, month);
    if (budget.tag case final tag?) return spentOnTag(tag, year, month);
    var total = 0;
    for (final e in _entries.inMonth(year, month)) {
      for (final (name, value) in e.spendingParts) {
        if (name == budget.category) total += value;
      }
    }
    return total;
  }

  /// [budget]'s limit for [year]/[month]: with [Budget.carry], plus what
  /// was left of it the month before, when it counted then. Only the
  /// month before: a leftover does not pile up.
  int allowance(Budget budget, int year, int month) {
    if (!budget.carry || budget.limit == 0) return budget.limit;
    final last = DateTime.utc(year, month - 1);
    final since = budget.since;
    if (since != null && last.isBefore(since)) return budget.limit;
    final left = budget.limit - spentAgainst(budget, last.year, last.month);
    return budget.limit + (left > 0 ? left : 0);
  }
}
