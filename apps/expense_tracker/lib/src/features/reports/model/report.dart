import 'dart:math';

import '../../../core/ledger/ledger.dart';
import 'report_period.dart';
import '../../../core/formatting/dates.dart';

// The figures of one period, worked out once for every tab.

/// What came in and went out in one stretch of a report, a week or a
/// month; one still ahead has [ahead] set and no figures.
final class StretchSum {
  const StretchSum(this.label, this.income, this.expense, {this.ahead = false});

  final String label;
  final int income;
  final int expense;
  final bool ahead;
}

/// Every sum the page shows for one period, worked out together. Entries
/// are read a month at a time from the ledger's index of months, so a
/// stretch costs only its own months rather than the whole book.
final class Report {
  Report._({
    required this.today,
    required this.stretches,
    required this.income,
    required this.expense,
    required this.dividends,
    required this.lastExpense,
    required this.buckets,
    required this.peak,
    required this.perStretch,
    required this.worthBefore,
    required this.worthNow,
    required this.worth,
    required this.spending,
    required this.lastSpending,
    required this.names,
    required this.largest,
    required this.merchants,
    required this.tags,
    required this.count,
    required this.days,
    required this.biggestSpend,
    required this.weekdays,
  });

  factory Report.of(
    ReportPeriod period, {
    required EntryReader entries,
    required ReportService reports,
    required BalanceService balances,
    required DateTime today,
  }) {
    final from = period.from;
    final to = period.to;
    final until = to.isAfter(today) ? today : to;
    final stretches = period.stretches;
    final inPeriod = entriesBetween(entries, from, to);
    var income = 0;
    var expense = 0;
    var dividends = 0;
    Entry? biggest;
    final days = <DateTime>{};
    final weekdays = List.filled(7, 0);
    for (final e in inPeriod) {
      income += e.earning;
      expense += e.spending;
      weekdays[weekdayIndex(e.date)] += e.spending;
      dividends += e.dividendNet;
      days.add(e.date);
      if (e.type == EntryType.expense &&
          (biggest == null || e.spending > biggest.spending)) {
        biggest = e;
      }
    }
    final before = _yearAgo(entries, from, until);
    final lastExpense = before.fold(0, (sum, e) => sum + e.spending);
    final buckets = [
      for (final (label, a, b) in stretches)
        if (a.isAfter(today))
          StretchSum(label, 0, 0, ahead: true)
        else
          _bucket(label, entriesBetween(entries, a, b)),
    ];
    final passed = [
      for (final (i, b) in buckets.indexed)
        if (!b.ahead) i,
    ];
    final peak = passed.isEmpty
        ? null
        : passed.reduce(
            (a, b) => buckets[b].expense > buckets[a].expense ? b : a,
          );
    // The ledger's own sum keeps the categories in the order it always
    // has, so equal amounts keep their places.
    final spending = reports.spendingBetween(from, to);
    final lastSpending = _spendingOf(before);
    final names = spending.keys.toList()
      ..sort((a, b) => spending[b]!.compareTo(spending[a]!));

    return Report._(
      today: today,
      stretches: stretches,
      income: income,
      expense: expense,
      dividends: dividends,
      lastExpense: lastExpense,
      buckets: buckets,
      peak: peak,
      perStretch: passed.isEmpty ? 0 : expense ~/ passed.length,
      worthBefore: balances.netWorthAt(from.subtract(const Duration(days: 1))),
      worthNow: balances.netWorthAt(until),
      worth: [
        for (final (_, a, b) in stretches)
          a.isAfter(today)
              ? null
              : balances.netWorthAt(b.isAfter(today) ? today : b),
      ],
      spending: spending,
      lastSpending: lastSpending,
      names: names,
      largest: names.fold(
        1,
        (m, n) => max(m, max(spending[n] ?? 0, lastSpending[n] ?? 0)),
      ),
      merchants: reports.merchantsBetween(from, to).take(5).toList(),
      tags: reports.tagsBetween(from, to),
      count: inPeriod.length,
      days: days.length,
      biggestSpend: biggest,
      weekdays: weekdays,
    );
  }

  final DateTime today;
  final List<ReportStretch> stretches;
  final int income;
  final int expense;
  final int dividends;

  /// Spending over the same days a year before.
  final int lastExpense;
  final List<StretchSum> buckets;

  /// The stretch that spent the most, of those begun.
  final int? peak;
  final int perStretch;
  final int worthBefore;
  final int worthNow;

  /// Net worth at the end of each stretch; null for those to come.
  final List<int?> worth;

  /// Spending by category, now and a year before.
  final Map<String, int> spending;
  final Map<String, int> lastSpending;

  /// The categories spent on, largest first.
  final List<String> names;

  /// The scale of the category bars.
  final int largest;
  final List<(String, int, int)> merchants;
  final List<(String, int)> tags;

  /// How many entries, on how many days.
  final int count;
  final int days;

  /// The largest single spending.
  final Entry? biggestSpend;

  /// Spending on each day of the week, Sunday first.
  final List<int> weekdays;

  /// The same day a year earlier, the 29th of February becoming the 28th.
  static DateTime _yearBefore(DateTime day) => DateTime.utc(
    day.year - 1,
    day.month,
    min(day.day, DateTime.utc(day.year - 1, day.month + 1, 0).day),
  );

  /// The entries from [from] to [to], read from those months only.
  static List<Entry> entriesBetween(
    EntryReader entries,
    DateTime from,
    DateTime to,
  ) => [
    for (
      var m = DateTime.utc(from.year, from.month);
      !m.isAfter(to);
      m = DateTime.utc(m.year, m.month + 1)
    )
      for (final e in entries.inMonth(m.year, m.month))
        if (!e.date.isBefore(from) && !e.date.isAfter(to)) e,
  ];

  /// The entries of [period] spent (in whole or in part) under the
  /// category [name], latest first, and how much of them was.
  static (List<Entry>, int) spentUnder(
    String name,
    EntryReader entries,
    ReportPeriod period,
  ) {
    final under = [
      for (final e in entriesBetween(entries, period.from, period.to))
        if (e.spendingParts.any((p) => p.$1 == name)) e,
    ]..sort((a, b) => b.date.compareTo(a.date));
    var total = 0;
    for (final e in under) {
      for (final (category, amount) in e.spendingParts) {
        if (category == name) total += amount;
      }
    }
    return (under, total);
  }

  /// The entries of the same days a year before.
  static List<Entry> _yearAgo(
    EntryReader entries,
    DateTime from,
    DateTime to,
  ) => entriesBetween(entries, _yearBefore(from), _yearBefore(to));

  static StretchSum _bucket(String label, List<Entry> entries) {
    var income = 0;
    var expense = 0;
    for (final e in entries) {
      income += e.earning;
      expense += e.spending;
    }
    return StretchSum(label, income, expense);
  }

  /// Spending by category name, split entries counted in their parts.
  static Map<String, int> _spendingOf(List<Entry> entries) {
    final totals = <String, int>{};
    for (final e in entries) {
      for (final (name, value) in e.spendingParts) {
        totals[name] = (totals[name] ?? 0) + value;
      }
    }
    return totals;
  }
}
