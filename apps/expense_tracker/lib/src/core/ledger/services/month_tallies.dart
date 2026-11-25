import 'package:core/time/utc_days.dart' show monthStarts;

import '../models/models.dart';
import '../repositories/entry_repository.dart';

/// What the reads over the whole book (the merchants, the tags, when each
/// account was last used, the latest spending at each merchant) count,
/// counted a month at a time and kept with each month's list: a save makes
/// a new list of the months it touches only, so the reads after it count
/// those months again and add up the rest as kept (review 32 1.2), rather
/// than going through every entry.
///
/// Each read gives what one pass over the entries in the order written
/// gives, the order of first appearance included: each month's count
/// keeps where in that order each name first appears ([EntryReader.orderOf]),
/// and the months' counts are put together by it.
final class MonthTallies {
  MonthTallies(this._entries);

  final EntryReader _entries;

  /// Each month's counts, kept with the month's list.
  static final _kept = Expando<_Tally>('monthTally');

  /// Each month's counts as of [today], the oldest month first.
  List<_Tally> _months(DateTime today) => [
    // Exception to as-of-today: each month's counts take its entries
    // through countsOn themselves.
    for (final month in _entries.newestMonths) _tallyOf(month, today),
  ].reversed.toList();

  _Tally _tallyOf(List<Entry> month, DateTime today) {
    // A month is newest first: its first entry is its latest. A month
    // with none later than today counts the same on any day since.
    final planned = month.first.date.isAfter(today);
    final kept = _kept[month];
    if (kept != null && kept.today == (planned ? today : null)) return kept;
    return _kept[month] = _Tally(month, planned ? today : null, _entries);
  }

  /// The entries that count [today] from [since] on, each with its place
  /// in the order written: read from the months they fall in.
  Iterable<(Entry, int)> lately(DateTime since, DateTime today) sync* {
    for (final m in monthStarts(since, today)) {
      // Exception to as-of-today: taken through countsOn just below.
      final month = _entries.inMonth(m.year, m.month);
      if (month.isEmpty) continue;
      final places = _tallyOf(month, today)._places;
      for (var i = 0; i < month.length; i++) {
        final e = month[i];
        if (countsOn(e.date, today) && !e.date.isBefore(since)) {
          yield (e, places[i]);
        }
      }
    }
  }

  /// The last day each account was used on, as the one an entry is of or
  /// the one it moves money to, among the entries that count [today]; in
  /// the order each was first used.
  Map<String, DateTime> lastUsedOn(DateTime today) {
    final merged = <String, (_At, DateTime)>{};
    for (final tally in _months(today)) {
      for (final MapEntry(key: id, value: (first, last))
          in tally.lastUsed.entries) {
        final had = merged[id];
        merged[id] = had == null
            ? (first, last)
            : (_earlier(first, had.$1), last.isAfter(had.$2) ? last : had.$2);
      }
    }
    return Map.unmodifiable({
      for (final id in _inOrder(merged, (v) => v.$1)) id: merged[id]!.$2,
    });
  }

  /// Every merchant written, in the order first written, with how many
  /// entries that count [today] name it.
  Map<String, int> merchantUses(DateTime today) {
    final merged = <String, (_At, int)>{};
    for (final tally in _months(today)) {
      for (final MapEntry(key: name, value: (first, uses))
          in tally.merchants.entries) {
        final had = merged[name];
        merged[name] = had == null
            ? (first, uses)
            : (_earlier(first, had.$1), had.$2 + uses);
      }
    }
    return {
      for (final name in _inOrder(merged, (v) => v.$1)) name: merged[name]!.$2,
    };
  }

  /// The latest spending at each merchant that counts [today]: of the
  /// latest day, the last written.
  Map<String, Entry> latestSpending(DateTime today) {
    final latest = <String, Entry>{};
    for (final tally in _months(today)) {
      // Months oldest first: a later month's latest is later.
      latest.addAll(tally.latest);
    }
    return latest;
  }

  /// Every tag on an entry that counts [today], with how many carry it and
  /// their spending, in the order first carried.
  List<(String, int, int)> tagUses(DateTime today) {
    final merged = <String, (_At, int, int)>{};
    for (final tally in _months(today)) {
      for (final MapEntry(key: tag, value: (first, uses, spent))
          in tally.tags.entries) {
        final had = merged[tag];
        merged[tag] = had == null
            ? (first, uses, spent)
            : (_earlier(first, had.$1), had.$2 + uses, had.$3 + spent);
      }
    }
    return [
      for (final tag in _inOrder(merged, (v) => v.$1))
        (tag, merged[tag]!.$2, merged[tag]!.$3),
    ];
  }

  /// Every tag written, on any entry, in the order first written.
  List<String> tagsWritten(DateTime today) {
    final merged = <String, _At>{};
    for (final tally in _months(today)) {
      for (final MapEntry(key: tag, value: first) in tally.known.entries) {
        final had = merged[tag];
        merged[tag] = had == null ? first : _earlier(first, had);
      }
    }
    return _inOrder(merged, (v) => v);
  }

  /// Spending by merchant among the entries that count [today], with how
  /// many times each was paid: each merchant as a read of the months,
  /// oldest first and each in its own order, first finds it.
  List<(String, int, int)> merchantSpending(DateTime today) {
    final amounts = <String, int>{};
    final counts = <String, int>{};
    for (final tally in _months(today)) {
      for (final MapEntry(key: name, value: (amount, count))
          in tally.spending.entries) {
        amounts[name] = (amounts[name] ?? 0) + amount;
        counts[name] = (counts[name] ?? 0) + count;
      }
    }
    return [
      for (final MapEntry(:key, :value) in amounts.entries)
        (key, counts[key] ?? 0, value),
    ];
  }

  /// The keys of [merged] by where each was first written ([firstOf]).
  static List<String> _inOrder<V>(
    Map<String, V> merged,
    _At Function(V value) firstOf,
  ) => merged.keys.toList()
    ..sort(
      (a, b) => _compare(firstOf(merged[a] as V), firstOf(merged[b] as V)),
    );
}

/// Where a name was met in one pass over the entries in the order
/// written: the entry's place ([EntryReader.orderOf]), then where in the
/// entry (its account before the one it moves money to, its tags in
/// turn).
typedef _At = (int, int);

int _compare(_At a, _At b) {
  final byPlace = a.$1.compareTo(b.$1);
  return byPlace != 0 ? byPlace : a.$2.compareTo(b.$2);
}

/// The earlier of [a] and [b].
_At _earlier(_At a, _At b) => _compare(a, b) <= 0 ? a : b;

/// One month's counts, each worked out on its first read: of the entries
/// that count on [today], or of all of them when none is later than any
/// day it is read on (null).
final class _Tally {
  _Tally(this._month, this.today, this._entries);

  final List<Entry> _month;
  final DateTime? today;
  final EntryReader _entries;

  bool _counts(Entry e) => switch (today) {
    final day? => countsOn(e.date, day),
    null => true,
  };

  /// Where each entry stands in the order written, in the month's order.
  late final List<int> _places = [
    for (final e in _month) _entries.orderOf(e.id),
  ];

  /// Each account's first use and last day.
  late final Map<String, (_At, DateTime)> lastUsed = () {
    final found = <String, (_At, DateTime)>{};
    for (var i = 0; i < _month.length; i++) {
      final e = _month[i];
      if (!_counts(e)) continue;
      void use(String id, _At first) {
        final had = found[id];
        found[id] = had == null
            ? (first, e.date)
            : (
                _earlier(first, had.$1),
                e.date.isAfter(had.$2) ? e.date : had.$2,
              );
      }

      use(e.account, (_places[i], 0));
      if (e.to case final to?) use(to, (_places[i], 1));
    }
    return found;
  }();

  /// Each merchant's first place, of every entry, and its uses counted.
  late final Map<String, (_At, int)> merchants = () {
    final found = <String, (_At, int)>{};
    for (var i = 0; i < _month.length; i++) {
      final e = _month[i];
      if (e.merchant.isEmpty) continue;
      final use = _counts(e) ? 1 : 0;
      final at = (_places[i], 0);
      final had = found[e.merchant];
      found[e.merchant] = had == null
          ? (at, use)
          : (_earlier(at, had.$1), had.$2 + use);
    }
    return found;
  }();

  /// The latest spending at each merchant: the month is newest day first,
  /// the last written first within a day, so the first found.
  late final Map<String, Entry> latest = {
    for (final e in _month.reversed)
      if (e.merchant.isNotEmpty && e.type == EntryType.expense && _counts(e))
        e.merchant: e,
  };

  /// Each tag's first use, uses and spending, of the entries counted.
  late final Map<String, (_At, int, int)> tags = () {
    final found = <String, (_At, int, int)>{};
    for (var i = 0; i < _month.length; i++) {
      final e = _month[i];
      if (e.tags.isEmpty || !_counts(e)) continue;
      for (final (k, tag) in e.tags.indexed) {
        final at = (_places[i], k);
        final had = found[tag];
        found[tag] = had == null
            ? (at, 1, e.spending)
            : (_earlier(at, had.$1), had.$2 + 1, had.$3 + e.spending);
      }
    }
    return found;
  }();

  /// Each tag's first use, of every entry.
  late final Map<String, _At> known = () {
    final found = <String, _At>{};
    for (var i = 0; i < _month.length; i++) {
      for (final (k, tag) in _month[i].tags.indexed) {
        final at = (_places[i], k);
        final had = found[tag];
        found[tag] = had == null ? at : _earlier(at, had);
      }
    }
    return found;
  }();

  /// Spending and payments at each merchant, of the entries counted, in
  /// the order the month lists them.
  late final Map<String, (int, int)> spending = () {
    final found = <String, (int, int)>{};
    for (final e in _month) {
      if (e.type != EntryType.expense || e.merchant.isEmpty) continue;
      if (!_counts(e)) continue;
      final had = found[e.merchant];
      found[e.merchant] = had == null
          ? (e.spending, 1)
          : (had.$1 + e.spending, had.$2 + 1);
    }
    return found;
  }();
}
