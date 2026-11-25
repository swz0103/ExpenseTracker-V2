import '../cache/query_cache.dart';
import 'tracked_readers.dart';
import '../models/models.dart';
import '../repositories/account_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/entry_repository.dart';
import 'balance_service.dart';
import 'month_tallies.dart';

import 'package:core/time/utc_days.dart';

/// Sums the screens show: a month's or any stretch of days' income and
/// spending, by category, merchant and tag, and what a person still owes.
final class ReportService {
  ReportService({
    required EntryReader entries,
    required AccountReader accounts,
    required CategoryReader categories,
    required this._balances,
    required this._cache,
    required this._today,
  }) : _entries = TrackedEntryReader(entries, _cache),
       _accounts = TrackedAccountReader(accounts, _cache),
       _categories = TrackedCategoryReader(categories, _cache);

  final EntryReader _entries;

  /// The whole-book counts, a month at a time.
  late final _tallies = MonthTallies(_entries);
  final AccountReader _accounts;
  final CategoryReader _categories;
  final BalanceService _balances;
  final QueryCache _cache;
  final DateTime Function() _today;

  /// The entries of [year]/[month] that count today ([countsOn]): a
  /// 預定 entry, dated later, counts once its day comes (D25).
  Iterable<Entry> _inMonth(int year, int month) =>
      countedOn(_entries.inMonth(year, month), _today());

  /// Income of a month, dividends included.
  int income(int year, int month) =>
      _inMonth(year, month).fold(0, (total, e) => total + e.earning);

  /// Spending of a month, less refunds, with transfer fees; with
  /// [account], only what was spent from it, as its card says (D20):
  /// transfers out, card payments and money lent are not spending.
  int expense(int year, int month, {int? untilDay, String? account}) =>
      _inMonth(year, month)
          .where((e) => untilDay == null || e.date.day <= untilDay)
          .where((e) => account == null || e.account == account)
          .fold(0, (total, e) => total + e.spending);

  /// What [entries] earned and spent, of those that count today
  /// ([countedOn]): the sums of a list as shown, where a 預定 entry is
  /// listed, marked, and counted once its day comes (D25).
  ({int income, int expense}) totalsOf(Iterable<Entry> entries) {
    var income = 0;
    var expense = 0;
    for (final e in countedOn(entries, _today())) {
      income += e.earning;
      expense += e.spending;
    }
    return (income: income, expense: expense);
  }

  int dividends(int year, int month) =>
      _inMonth(year, month).fold(0, (sum, e) => sum + e.dividendNet);

  int spentOn(DateTime day) => countedOn(
    _entries.onDay(day),
    _today(),
  ).fold(0, (total, e) => total + e.spending);

  /// The entries from [from] to [to], both counted, that count today
  /// ([countsOn]).
  Iterable<Entry> _between(DateTime from, DateTime to) =>
      countedOn(_allBetween(from, to), _today());

  /// The entries from [from] to [to], both counted, read a month at a
  /// time from the month index rather than through every entry.
  Iterable<Entry> _allBetween(DateTime from, DateTime to) sync* {
    for (final m in monthStarts(from, to)) {
      // Exception to as-of-today: read only through _between, which takes it
      // through countedOn.
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

  /// What [person] still owes, payment by payment: each entry that
  /// raised their account's balance (a sum paid for them, as it arrived
  /// in the account's currency), with what is left of it once whatever
  /// lowered the balance (what they paid back, anything else kept on the
  /// account) is taken off the oldest first, after what they owed from
  /// the start; those paid off are left out. Newest first. Each entry
  /// counts what it does to the balance ([BalanceService.effect]), so
  /// what is listed adds up to the balance whenever it is owed and the
  /// account started at nothing.
  List<(Entry, int)> owedBy(String person) =>
      _cache.remember(('owedBy', person, _today()), () {
        final moves = [
          for (final e in _balances.entriesOf(person).reversed)
            if (countsOn(e.date, _today())) e,
        ];
        // What they owed from the start is paid back before anything lent.
        var back = -_accounts.resolve(person).opening;
        final lent = <(Entry, int)>[];
        for (final e in moves) {
          final change = _balances.effect(e, person);
          if (change > 0) {
            lent.add((e, change));
          } else {
            back -= change;
          }
        }
        final owed = <(Entry, int)>[];
        for (final (e, amount) in lent) {
          final taken = back <= 0
              ? 0
              : back < amount
              ? back
              : amount;
          back -= taken;
          if (amount > taken) owed.add((e, amount - taken));
        }
        return owed.reversed.toList();
      });

  /// Every tag with how many entries carry it and their spending, most
  /// used first: of the entries that count today ([countsOn]), so a 預定
  /// entry joins on its day (D71), as the budgets by tag count it.
  List<(String, int, int)> get tagStats =>
      _cache.remember(('tagStats', _today()), _tagStats);

  List<(String, int, int)> _tagStats() =>
      _tallies.tagUses(_today())..sort((a, b) => b.$2.compareTo(a.$2));

  /// Every merchant with how many entries name it and their spending,
  /// most used first: worked out once per change of the entries. Those
  /// used alike, by spending, largest first ([merchantsBetween] from the
  /// first day to today).
  List<(String, int, int)> get merchantStats => _cache.remember(
    ('merchantStats', _today()),
    () => List.unmodifiable(
      _tallies.merchantSpending(_today())
        ..sort((a, b) => b.$3.compareTo(a.$3))
        ..sort((a, b) => b.$2.compareTo(a.$2)),
    ),
  );

  /// Every tag in use, most used first ([tagStats]), then those only on
  /// 預定 entries: the names offered to pick from.
  List<String> get tags => _cache.remember(('tags', _today()), () {
    final used = [for (final (tag, _, _) in tagStats) tag];
    final counted = used.toSet();
    // A tag only on a 預定 entry is still one to pick, in the order
    // first written.
    return [
      ...used,
      for (final tag in _tallies.tagsWritten(_today()))
        if (!counted.contains(tag)) tag,
    ];
  });

  /// Open spending or [income] categories, the most used over this month
  /// and the last first, so a new entry or recurring item starts on the
  /// likely one; a 預定 entry is a use once its day comes. Worked out once
  /// a day per change of the entries or categories.
  List<String> categoriesByUse({required bool income}) =>
      _cache.remember(('categoriesByUse', income, _today()), () {
        final type = income ? EntryType.income : EntryType.expense;
        final counts = <String, int>{};
        for (final back in const [0, 1]) {
          final month = monthStart(_today(), -back);
          for (final e in countedOn(
            _entries.inMonth(month.year, month.month),
            _today(),
          )) {
            if (e.type == type) {
              counts[e.category] = (counts[e.category] ?? 0) + 1;
            }
          }
        }
        final names = [
          for (final c in _categories.forEntries(income: income)) c.name,
        ];
        return List<String>.unmodifiable(
          names..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0)),
        );
      });
}
