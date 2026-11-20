import '../cache/query_cache.dart';
import 'tracked_readers.dart';
import '../models/models.dart';
import '../repositories/account_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/entry_repository.dart';

/// Sums the screens show: a month's or any stretch of days' income and
/// spending, by category, merchant and tag, and what a person still owes.
final class ReportService {
  ReportService({
    required EntryReader entries,
    required AccountReader accounts,
    required CategoryReader categories,
    required this._cache,
    required this._today,
  }) : _entries = TrackedEntryReader(entries, _cache),
       _accounts = TrackedAccountReader(accounts, _cache),
       _categories = TrackedCategoryReader(categories, _cache);

  final EntryReader _entries;
  final AccountReader _accounts;
  final CategoryReader _categories;
  final QueryCache _cache;
  final DateTime Function() _today;

  /// Income of a month, dividends included.
  int income(int year, int month) =>
      _entries.inMonth(year, month).fold(0, (total, e) => total + e.earning);

  /// Spending of a month, less refunds, with transfer fees.
  int expense(int year, int month, {int? untilDay}) => _entries
      .inMonth(year, month)
      .where((e) => untilDay == null || e.date.day <= untilDay)
      .fold(0, (total, e) => total + e.spending);

  int dividends(int year, int month) =>
      _entries.inMonth(year, month).fold(0, (sum, e) => sum + e.dividendNet);

  int spentOn(DateTime day) =>
      _entries.onDay(day).fold(0, (total, e) => total + e.spending);

  /// The entries from [from] to [to], both counted, read a month at a
  /// time from the month index rather than through every entry.
  Iterable<Entry> _between(DateTime from, DateTime to) sync* {
    for (
      var m = DateTime.utc(from.year, from.month);
      !m.isAfter(to);
      m = DateTime.utc(m.year, m.month + 1)
    ) {
      for (final e in _entries.inMonth(m.year, m.month)) {
        if (!e.date.isBefore(from) && !e.date.isAfter(to)) yield e;
      }
    }
  }

  /// Income, dividends included, and spending from [from] to [to].
  (int, int) totalsBetween(DateTime from, DateTime to) {
    var income = 0;
    var expense = 0;
    for (final e in _between(from, to)) {
      income += e.earning;
      expense += e.spending;
    }
    return (income, expense);
  }

  /// Spending by category name from [from] to [to].
  Map<String, int> spendingBetween(DateTime from, DateTime to) {
    final totals = <String, int>{};
    for (final e in _between(from, to)) {
      for (final (name, value) in e.spendingParts) {
        totals[name] = (totals[name] ?? 0) + value;
      }
    }
    return totals;
  }

  /// Spending by merchant from [from] to [to], largest first, with how
  /// many times each was paid.
  List<(String, int, int)> merchantsBetween(DateTime from, DateTime to) {
    final amounts = <String, int>{};
    final counts = <String, int>{};
    for (final e in _between(from, to)) {
      if (e.type != EntryType.expense || e.merchant.isEmpty) continue;
      amounts[e.merchant] = (amounts[e.merchant] ?? 0) + e.spending;
      counts[e.merchant] = (counts[e.merchant] ?? 0) + 1;
    }
    final rows = [
      for (final MapEntry(:key, :value) in amounts.entries)
        (key, counts[key] ?? 0, value),
    ];
    rows.sort((a, b) => b.$3.compareTo(a.$3));
    return rows;
  }

  /// Spending by tag from [from] to [to], largest first.
  List<(String, int)> tagsBetween(DateTime from, DateTime to) {
    final totals = <String, int>{};
    for (final e in _between(from, to)) {
      if (e.spending == 0) continue;
      for (final tag in e.tags) {
        totals[tag] = (totals[tag] ?? 0) + e.spending;
      }
    }
    final rows = [
      for (final MapEntry(:key, :value) in totals.entries) (key, value),
    ];
    rows.sort((a, b) => b.$2.compareTo(a.$2));
    return rows;
  }

  /// The day of the first entry, where the book starts.
  DateTime get firstDay => _entries.firstDate ?? _today();

  /// What [person] still owes, payment by payment: each sum paid for
  /// them, with what is left of it once what they paid back is taken off
  /// the oldest first, after what they owed from the start; those paid
  /// off are left out. Newest first.
  List<(Entry, int)> owedBy(String person) =>
      _cache.remember(('owedBy', person), () {
        final moves = [
          for (final e in _entries.all)
            if (e.type == EntryType.transfer &&
                (e.to == person || e.account == person))
              e,
        ]..sort((a, b) => a.date.compareTo(b.date));
        // What they owed from the start is paid back before anything lent.
        var back = -_accounts.resolve(person).opening;
        final lent = <Entry>[];
        for (final e in moves) {
          if (e.to == person) {
            lent.add(e);
          } else {
            back += e.amount;
          }
        }
        final owed = <(Entry, int)>[];
        for (final e in lent) {
          final taken = back <= 0
              ? 0
              : back < e.amount
              ? back
              : e.amount;
          back -= taken;
          if (e.amount > taken) owed.add((e, e.amount - taken));
        }
        return owed.reversed.toList();
      });

  /// Every tag with how many entries carry it and their spending, most
  /// used first.
  List<(String, int, int)> get tagStats =>
      _cache.remember('tagStats', _tagStats);

  List<(String, int, int)> _tagStats() {
    final counts = <String, int>{};
    final sums = <String, int>{};
    for (final e in _entries.all) {
      for (final tag in e.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
        sums[tag] = (sums[tag] ?? 0) + e.spending;
      }
    }
    return [
      for (final MapEntry(:key, :value) in counts.entries)
        (key, value, sums[key] ?? 0),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
  }

  /// Every merchant with how many entries name it and their spending,
  /// most used first.
  List<(String, int, int)> get merchantStats =>
      merchantsBetween(firstDay, _today())
        ..sort((a, b) => b.$2.compareTo(a.$2));

  /// Every tag in use, most used first.
  List<String> get tags => [for (final (tag, _, _) in tagStats) tag];

  /// Open spending or [income] categories, the most used over this month
  /// and the last first, so a new entry starts on the likely one.
  List<String> categoriesByUse({required bool income}) {
    final type = income ? EntryType.income : EntryType.expense;
    final counts = <String, int>{};
    for (final back in const [0, 1]) {
      final month = DateTime.utc(_today().year, _today().month - back);
      for (final e in _entries.inMonth(month.year, month.month)) {
        if (e.type == type) counts[e.category] = (counts[e.category] ?? 0) + 1;
      }
    }
    final names = [
      for (final c in _categories.forEntries(income: income)) c.name,
    ];
    return names..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
  }
}
