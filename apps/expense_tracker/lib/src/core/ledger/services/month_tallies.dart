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

  /// [part] of each month's counts as of [today] put together, by name.
  Map<String, _Seen> _merged(
    DateTime today,
    Map<String, _Seen> Function(_Tally tally) part,
  ) {
    final merged = <String, _Seen>{};
    for (final tally in _months(today)) {
      for (final MapEntry(:key, :value) in part(tally).entries) {
        final had = merged[key];
        if (had == null) {
          merged[key] = value.copy();
        } else {
          had.join(value);
        }
      }
    }
    return merged;
  }

  /// The names of [merged] in the order first written.
  static List<String> _inOrder(Map<String, _Seen> merged) =>
      merged.keys.toList()..sort((a, b) => merged[a]!.compareTo(merged[b]!));

  /// The last day each account was used on, as the one an entry is of or
  /// the one it moves money to, among the entries that count [today]; in
  /// the order each was first used.
  Map<String, DateTime> lastUsedOn(DateTime today) {
    final merged = _merged(today, (t) => t.lastUsed);
    return Map.unmodifiable({
      for (final id in _inOrder(merged)) id: merged[id]!.last!,
    });
  }

  /// Every merchant written, in the order first written, with how many
  /// entries that count [today] name it.
  Map<String, int> merchantUses(DateTime today) {
    final merged = _merged(today, (t) => t.merchants);
    return {for (final name in _inOrder(merged)) name: merged[name]!.count};
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
    final merged = _merged(today, (t) => t.tags);
    return [
      for (final tag in _inOrder(merged))
        (tag, merged[tag]!.count, merged[tag]!.sum),
    ];
  }

  /// Every tag written, on any entry, in the order first written.
  List<String> tagsWritten(DateTime today) =>
      _inOrder(_merged(today, (t) => t.known));

  /// Spending by merchant among the entries that count [today], with how
  /// many times each was paid: each merchant as a read of the months,
  /// oldest first and each in its own order, first finds it.
  List<(String, int, int)> merchantSpending(DateTime today) {
    final merged = <String, _Seen>{};
    for (final tally in _months(today)) {
      for (final MapEntry(:key, :value) in tally.spending.entries) {
        final had = merged[key];
        if (had == null) {
          merged[key] = value.copy();
        } else {
          had.join(value);
        }
      }
    }
    return [
      for (final MapEntry(:key, :value) in merged.entries)
        (key, value.count, value.sum),
    ];
  }
}

/// A name met in the entries: where first, in one pass over them in the
/// order written (the entry's place, [EntryReader.orderOf], then where in
/// the entry: its account before the one it moves money to, its tags in
/// turn), how many times, their sum and the latest day.
final class _Seen {
  _Seen(this.place, this.index);

  int place;
  int index;
  var count = 0;
  var sum = 0;
  DateTime? last;

  /// Notes one more, met at [place] and [index].
  void meet(int place, int index) {
    if (place < this.place || (place == this.place && index < this.index)) {
      this.place = place;
      this.index = index;
    }
  }

  void day(DateTime date) {
    final had = last;
    if (had == null || date.isAfter(had)) last = date;
  }

  _Seen copy() => _Seen(place, index)
    ..count = count
    ..sum = sum
    ..last = last;

  /// Takes [other]'s in as well.
  void join(_Seen other) {
    meet(other.place, other.index);
    count += other.count;
    sum += other.sum;
    if (other.last case final date?) day(date);
  }

  int compareTo(_Seen other) {
    final byPlace = place.compareTo(other.place);
    return byPlace != 0 ? byPlace : index.compareTo(other.index);
  }
}

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

  /// [found]'s [name], met at [i] (and [index] within the entry).
  _Seen _meet(Map<String, _Seen> found, String name, int i, int index) {
    final had = found[name];
    if (had == null) return found[name] = _Seen(_places[i], index);
    return had..meet(_places[i], index);
  }

  /// Each account's first use and last day.
  late final Map<String, _Seen> lastUsed = () {
    final found = <String, _Seen>{};
    for (var i = 0; i < _month.length; i++) {
      final e = _month[i];
      if (!_counts(e)) continue;
      _meet(found, e.account, i, 0).day(e.date);
      if (e.to case final to?) _meet(found, to, i, 1).day(e.date);
    }
    return found;
  }();

  /// Each merchant's first place, of every entry, and its uses counted.
  late final Map<String, _Seen> merchants = () {
    final found = <String, _Seen>{};
    for (var i = 0; i < _month.length; i++) {
      final e = _month[i];
      if (e.merchant.isEmpty) continue;
      final seen = _meet(found, e.merchant, i, 0);
      if (_counts(e)) seen.count++;
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
  late final Map<String, _Seen> tags = () {
    final found = <String, _Seen>{};
    for (var i = 0; i < _month.length; i++) {
      final e = _month[i];
      if (e.tags.isEmpty || !_counts(e)) continue;
      for (var k = 0; k < e.tags.length; k++) {
        _meet(found, e.tags[k], i, k)
          ..count += 1
          ..sum += e.spending;
      }
    }
    return found;
  }();

  /// Each tag's first use, of every entry.
  late final Map<String, _Seen> known = () {
    final found = <String, _Seen>{};
    for (var i = 0; i < _month.length; i++) {
      final tags = _month[i].tags;
      for (var k = 0; k < tags.length; k++) {
        _meet(found, tags[k], i, k);
      }
    }
    return found;
  }();

  /// Spending and payments at each merchant, of the entries counted, in
  /// the order the month lists them.
  late final Map<String, _Seen> spending = () {
    final found = <String, _Seen>{};
    for (final e in _month) {
      if (e.type != EntryType.expense || e.merchant.isEmpty) continue;
      if (!_counts(e)) continue;
      (found[e.merchant] ??= _Seen(0, 0))
        ..count += 1
        ..sum += e.spending;
    }
    return found;
  }();
}
