import 'dart:math' show max;

import 'package:ledger_entries/rules.dart' show spendingUnder;

import '../models/models.dart';
import '../repositories/category_repository.dart';
import '../repositories/entry_repository.dart';
import 'report_service.dart';

import 'package:core/time/utc_days.dart';

/// What has been spent against a budget, and where a month is heading.
final class BudgetService {
  BudgetService({
    required this._entries,
    required this._categories,
    required ReportService reportService,
    required this._today,
  }) : _reports = reportService;

  final EntryReader _entries;
  final CategoryReader _categories;
  final ReportService _reports;
  final DateTime Function() _today;

  /// The days of [year]/[month] gone by, today included, and all its
  /// days; every day of a month other than this one.
  (int, int) daysGone(int year, int month) {
    final days = monthEnd(year, month).day;
    final current = year == _today().year && month == _today().month;
    return (current ? _today().day : days, days);
  }

  /// What spending carrying [tag] came to in [year]/[month].
  int spentOnTag(String tag, int year, int month) {
    var total = 0;
    for (final e in countedOn(_entries.inMonth(year, month), _today())) {
      if (e.tags.contains(tag)) total += e.spending;
    }
    return total;
  }

  /// The day of a month from which its month-end [forecast] is shown:
  /// before it, a week's pace says too little.
  static const forecastFrom = 7;

  /// Where [spent], all spending of [year]/[month], is heading by the
  /// month's end at the pace so far (D64): only the month's own spending
  /// is scaled by its days; a refund of a purchase of an earlier month
  /// counts in what was spent but is not scaled, and the forecast is
  /// never below nothing. The month's spending for a month gone by.
  int forecast(int spent, int year, int month) {
    final (passed, days) = daysGone(year, month);
    if (passed >= days || passed == 0) return spent;
    final earlier = _earlierRefunds(year, month);
    final own = spent - earlier;
    final heading = own * days ~/ passed + _roundsUp(own * days, passed);
    return max(0, heading + earlier);
  }

  /// 1 when [numerator] / [denominator] rounds up, half away from zero.
  static int _roundsUp(int numerator, int denominator) {
    final rest = numerator.remainder(denominator).abs();
    if (rest * 2 < denominator) return 0;
    return numerator < 0 ? -1 : 1;
  }

  /// What the refunds of [year]/[month] that give back a purchase of an
  /// earlier month (or one no longer kept) take off its spending: a
  /// negative amount, or 0.
  int _earlierRefunds(int year, int month) {
    final first = DateTime.utc(year, month);
    var total = 0;
    for (final e in countedOn(_entries.inMonth(year, month), _today())) {
      final of = e.refundOf;
      if (of == null) continue;
      final original = _entries.byId(of);
      if (original == null || original.date.isBefore(first)) {
        total += e.spending;
      }
    }
    return total;
  }

  /// What 預算's two cards show of [spent], all spending of
  /// [year]/[month], against [total], the whole budget's allowance: for
  /// this month, what can still be spent a day and where the month is
  /// heading ([forecast], from [forecastFrom] days gone); for a month
  /// gone by, what was spent a day and what was saved.
  BudgetPace pace(int spent, int total, int year, int month) {
    final (passed, days) = daysGone(year, month);
    final current = year == _today().year && month == _today().month;
    if (!current) {
      return PastPace(days: days, perDay: spent ~/ days, saved: total - spent);
    }
    final left = total - spent;
    final remaining = days - passed + 1;
    return CurrentPace(
      daysLeft: remaining,
      perDay: left > 0 ? left ~/ remaining : 0,
      forecast: passed >= forecastFrom ? forecast(spent, year, month) : null,
      total: total,
    );
  }

  /// What counts against [budget] in [year]/[month]: all spending, the
  /// spending carrying its tag, or the share of spending under its
  /// category, its subcategories included (`spendingUnder`, D54); a 預定
  /// entry only once its day comes ([countsOn], D25).
  int spentAgainst(Budget budget, int year, int month) {
    if (budget.category == allSpending) return _reports.expense(year, month);
    if (budget.tag case final tag?) return spentOnTag(tag, year, month);
    var total = 0;
    for (final e in countedOn(_entries.inMonth(year, month), _today())) {
      total += spendingUnder(e, budget.category, _parentOf);
    }
    return total;
  }

  String? _parentOf(String name) => _categories.byName(name).parent;

  /// [budget]'s limit for [year]/[month]: with [Budget.carry], plus what
  /// was left of it the month before, when it counted then. Only the
  /// month before: a leftover does not pile up.
  int allowance(Budget budget, int year, int month) {
    if (!budget.carry || budget.limit == 0) return budget.limit;
    final last = monthStart(DateTime.utc(year, month), -1);
    final since = budget.since;
    if (since != null && last.isBefore(since)) return budget.limit;
    final left = budget.limit - spentAgainst(budget, last.year, last.month);
    return budget.limit + (left > 0 ? left : 0);
  }
}

/// What 預算's two cards show of a month's spending against the whole
/// budget ([BudgetService.pace]).
sealed class BudgetPace {
  const BudgetPace();
}

/// A month gone by: what was spent a day over its [days], and what was
/// [saved] against the budget (below nothing: over it).
final class PastPace extends BudgetPace {
  const PastPace({
    required this.days,
    required this.perDay,
    required this.saved,
  });

  final int days;
  final int perDay;
  final int saved;
}

/// This month: what can still be spent a day over the [daysLeft] days
/// left, today included, and where the month is heading ([forecast]),
/// null before [BudgetService.forecastFrom] days have gone.
final class CurrentPace extends BudgetPace {
  const CurrentPace({
    required this.daysLeft,
    required this.perDay,
    required this.forecast,
    required this.total,
  });

  final int daysLeft;
  final int perDay;
  final int? forecast;

  /// The whole budget's allowance the forecast is held against.
  final int total;

  /// Whether the month is heading past [total].
  bool get overBudget => (forecast ?? 0) > total;
}
