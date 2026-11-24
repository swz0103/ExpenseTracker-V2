import 'dart:collection';

import '../models/models.dart';

/// What the screens and queries may ask of the entries: no way to change
/// them.
abstract interface class EntryReader {
  /// Every entry in the order written; the list cannot be changed. An
  /// entry brought back from the trash or by an undo is back in its own
  /// place (D75), so this order is the entries' history, whatever was
  /// done since.
  List<Entry> get all;

  /// Where the entry [id] stands in the order written: its place, kept
  /// while it is in the trash. Every tie between entries of a day is
  /// broken by it (D76), never by where an entry happens to be held.
  int orderOf(String id);

  int get length;

  bool get isEmpty;

  /// The entry with [id], if it is still in the book.
  Entry? byId(String id);

  /// Entries in [year]/[month], newest day first; within a day the most
  /// recently recorded first. The list cannot be changed.
  List<Entry> inMonth(int year, int month);

  /// Entries on [day], in [inMonth] order.
  List<Entry> onDay(DateTime day);

  /// Every entry, the oldest day first and within a day in the order
  /// written: read from the month index, with nothing to sort.
  Iterable<Entry> get byDate;

  /// The day of the first entry; null when there is none.
  DateTime? get firstDate;

  /// How much of the entry with [id] has been refunded by entries that
  /// refund it.
  int refundedTotal(String id);

  /// A number that changes whenever an entry paid from or into [account]
  /// is added, taken away or changed, and whenever the book changes in a
  /// way not followed entry by entry: what was worked out for [account]
  /// alone still holds while it stays the same.
  int versionOf(String account);
}

/// The order every list of entries is shown in, newest first: by day,
/// then the later written first (D76), as [EntryReader.orderOf] keeps it.
/// The one tie-break, whatever the entries' place in memory.
Comparator<Entry> newestFirst(EntryReader book) => (a, b) {
  final byDay = b.date.compareTo(a.date);
  return byDay != 0 ? byDay : book.orderOf(b.id).compareTo(book.orderOf(a.id));
};

/// Every entry of the book, in the order written, with what is asked of
/// them again and again (by month, by day, by id, refunds) worked out
/// once, on the first ask, and then kept up to date as entries are added,
/// taken away or put in place of another: a change costs the entries of
/// one month, not of the whole book. A change that cannot be followed
/// cheaply (one in the middle of the list, many at once, an entry moved to
/// another day) throws the indexes away to be worked out again.
///
/// A list for the commands that write; the screens see an [EntryReader].
final class EntryRepository implements EntryReader {
  /// [entries] in the order written; [order] gives each its place, as
  /// the book kept it (each in turn when not given).
  EntryRepository([
    Iterable<Entry> entries = const [],
    Map<String, int> order = const {},
  ]) : _items = [...entries] {
    for (final (i, e) in _items.indexed) {
      _order[e.id] = order[e.id] ?? i;
    }
    for (final key in _order.values) {
      if (key >= _next) _next = key + 1;
    }
  }

  final List<Entry> _items;

  /// Each entry's place in the order written, by id: kept after it is
  /// taken away, for it to come back to.
  final _order = <String, int>{};

  /// The place of the next entry written.
  var _next = 0;

  @override
  int orderOf(String id) => _order[id] ?? _next;

  /// Notes that [place] is taken, as by an entry in the trash, so no entry
  /// written later is put before it; with [id], that it is that entry's,
  /// for it to come back to.
  void reserve(int place, {String? id}) {
    if (place >= _next) _next = place + 1;
    if (id != null) _order.putIfAbsent(id, () => place);
  }

  /// Puts [entry] back in its place [place] in the order written (D75):
  /// after every entry before it, before every entry after; last when
  /// [place] is null.
  void restoreAt(Entry entry, int? place) {
    if (place == null) return add(entry);
    reserve(place);
    var low = 0;
    var high = _items.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (orderOf(_items[middle].id) < place) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _order[entry.id] = place;
    if (low >= _items.length) {
      _items.add(entry);
      _noteAdded(entry);
    } else {
      _discard();
      _items.insert(low, entry);
    }
  }

  /// Takes the entries of [other] and where each stands, as when the book
  /// is read again.
  void replaceWith(EntryRepository other) {
    clear();
    _order
      ..clear()
      ..addAll(other._order);
    _next = other._next;
    _items.addAll(other._items);
  }

  /// More entries added at once than this are not followed one by one.
  static const _followed = 64;

  /// Each month's entries in [inMonth] order, a list that is never changed
  /// once handed out: a change puts a new one in its place.
  Map<int, List<Entry>>? _months;

  /// Entries put in place of others on the same day, not yet in [_months]:
  /// by month, each old entry and the one now standing for it. A run of
  /// them (a category renamed on thousands of entries) costs one pass over
  /// the month when it is next asked for, not one pass each.
  final _swaps = <int, Map<Entry, Entry>>{};

  /// For each entry in [_swaps], the one it stands for in [_months].
  final _stands = Map<Entry, Entry>.identity();

  Map<String, Entry>? _ids;
  Map<String, int>? _refunds;
  DateTime? _first;
  var _firstKnown = false;

  /// Bumped by a change not followed entry by entry: every account's
  /// [versionOf] changes with it.
  var _generation = 0;

  /// Changes to the entries of each account, followed one by one.
  final _changes = <String, int>{};

  void _touch(Entry e) {
    _changes[e.account] = (_changes[e.account] ?? 0) + 1;
    final to = e.to;
    if (to != null) _changes[to] = (_changes[to] ?? 0) + 1;
  }

  @override
  int versionOf(String account) => _generation << 32 | (_changes[account] ?? 0);

  void _discard() {
    _generation++;
    _months = null;
    _swaps.clear();
    _stands.clear();
    _ids = null;
    _refunds = null;
    _first = null;
    _firstKnown = false;
  }

  static int _monthOf(Entry e) => e.date.year * 12 + e.date.month;

  /// Puts the swaps of [month] into its entries.
  void _settle(int month) {
    final swaps = _swaps.remove(month);
    if (swaps == null) return;
    final months = _months;
    final bucket = months?[month];
    if (months != null && bucket != null) {
      months[month] = List.unmodifiable([
        for (final x in bucket) swaps[x] ?? x,
      ]);
    }
    for (final now in swaps.values) {
      _stands.remove(now);
    }
  }

  /// Notes that [e], now last in the list, has been added.
  void _noteAdded(Entry e) {
    _touch(e);
    final months = _months;
    if (months != null) {
      final month = _monthOf(e);
      _settle(month);
      final old = months[month] ?? const <Entry>[];
      // Sorted newest day first; the last written first within a day, and
      // [e] is the last written of all.
      var low = 0;
      var high = old.length;
      while (low < high) {
        final middle = (low + high) >> 1;
        if (old[middle].date.isAfter(e.date)) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      months[month] = List.unmodifiable([
        ...old.take(low),
        e,
        ...old.skip(low),
      ]);
    }
    _ids?[e.id] = e;
    if (e.refundOf case final of?) {
      final refunds = _refunds;
      if (refunds != null) refunds[of] = (refunds[of] ?? 0) + e.amount;
    }
    if (_firstKnown) {
      final first = _first;
      if (first == null || e.date.isBefore(first)) _first = e.date;
    }
  }

  /// Notes that [e] has been taken out of the list, from wherever it was.
  void _noteRemoved(Entry e) {
    _touch(e);
    final months = _months;
    if (months != null) {
      final month = _monthOf(e);
      _settle(month);
      final old = months[month];
      if (old != null) {
        final kept = [
          for (final x in old)
            if (!identical(x, e)) x,
        ];
        if (kept.isEmpty) {
          months.remove(month);
        } else {
          months[month] = List.unmodifiable(kept);
        }
      }
    }
    _ids?.remove(e.id);
    if (e.refundOf case final of?) {
      final refunds = _refunds;
      if (refunds != null) {
        final left = (refunds[of] ?? 0) - e.amount;
        if (left == 0) {
          refunds.remove(of);
        } else {
          refunds[of] = left;
        }
      }
    }
    // The first day may have gone with it.
    if (_firstKnown && _first == e.date) {
      _first = null;
      _firstKnown = false;
    }
  }

  // The list, with every change noticed.

  @override
  @override
  bool get isEmpty => _items.isEmpty;

  /// The place of the first entry that passes [test]; -1 when none does.
  int indexWhere(bool Function(Entry entry) test) => _items.indexWhere(test);

  /// Whether any entry passes [test].
  bool any(bool Function(Entry entry) test) => _items.any(test);

  @override
  int get length => _items.length;

  Entry operator [](int index) => _items[index];

  void operator []=(int index, Entry entry) {
    final old = _items[index];
    _items[index] = entry;
    _order.putIfAbsent(entry.id, () => orderOf(old.id));
    _touch(old);
    _touch(entry);
    if (old.id == entry.id && old.date == entry.date) {
      // A new version of the same entry, on the same day: the same place
      // in its month.
      _replaceInMonth(old, entry);
    } else {
      // Another entry, or another day: where it stands among that day's
      // entries depends on where each is in the list, which only the list
      // knows. (Another entry put here may be one moved from elsewhere in
      // the list, as a sort does.)
      _discard();
    }
  }

  void _replaceInMonth(Entry old, Entry entry) {
    if (_months != null) {
      final swaps = _swaps.putIfAbsent(
        _monthOf(old),
        Map<Entry, Entry>.identity,
      );
      // [old] may itself have been put there by an earlier swap: then it is
      // that swap's entry that stands in the month.
      final key = _stands.remove(old) ?? old;
      swaps[key] = entry;
      _stands[entry] = key;
    }
    final ids = _ids;
    if (ids != null) {
      ids.remove(old.id);
      ids[entry.id] = entry;
    }
    if (old.refundOf != null || entry.refundOf != null) _refunds = null;
  }

  void add(Entry element) {
    _order[element.id] = _next++;
    _items.add(element);
    _noteAdded(element);
  }

  void addAll(Iterable<Entry> iterable) {
    final added = iterable.toList();
    for (final e in added) {
      _order[e.id] = _next++;
    }
    _items.addAll(added);
    if (added.length > _followed) {
      _discard();
    } else {
      added.forEach(_noteAdded);
    }
  }

  void insert(int index, Entry element) {
    if (index >= _items.length) {
      _items.add(element);
      _order.putIfAbsent(element.id, () => _next++);
      return _noteAdded(element);
    }
    _order.putIfAbsent(element.id, () => _next++);
    _discard();
    _items.insert(index, element);
  }

  /// Takes away [element], this very entry; false when it is not held.
  bool remove(Entry element) {
    final index = _items.indexOf(element);
    if (index < 0) return false;
    removeAt(index);
    return true;
  }

  Entry removeAt(int index) {
    final removed = _items.removeAt(index);
    _noteRemoved(removed);
    return removed;
  }

  Entry removeLast() {
    final removed = _items.removeLast();
    _noteRemoved(removed);
    return removed;
  }

  void removeRange(int start, int end) {
    _discard();
    _items.removeRange(start, end);
  }

  void removeWhere(bool Function(Entry) test) {
    _discard();
    _items.removeWhere(test);
  }

  void clear() {
    _discard();
    _items.clear();
  }

  // The rest of what a list can do, each a change that cannot be followed
  // one entry at a time: done on the list itself, the indexes thrown away.

  // What is asked of them.

  /// Puts what [change] gives in place of each entry it gives one for,
  /// and returns those put in.
  List<Entry> changeAll(Entry? Function(Entry entry) change) {
    final changed = <Entry>[];
    for (var i = 0; i < _items.length; i++) {
      final next = change(_items[i]);
      if (next == null) continue;
      this[i] = next;
      changed.add(next);
    }
    return changed;
  }

  @override
  List<Entry> get all => UnmodifiableListView(_items);

  @override
  Entry? byId(String id) => (_ids ??= {for (final e in _items) e.id: e})[id];

  @override
  List<Entry> inMonth(int year, int month) {
    final months = _months ??= _indexMonths();
    _settle(year * 12 + month);
    return months[year * 12 + month] ?? const <Entry>[];
  }

  @override
  Iterable<Entry> get byDate sync* {
    final months = _months ??= _indexMonths();
    for (final month in months.keys.toList()..sort()) {
      _settle(month);
      // A month is kept newest first.
      yield* months[month]!.reversed;
    }
  }

  @override
  List<Entry> onDay(DateTime day) {
    final bucket = inMonth(day.year, day.month);
    // The month is sorted newest day first: the day's entries are together.
    var low = 0;
    var high = bucket.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (bucket[middle].date.isAfter(day)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    var end = low;
    while (end < bucket.length && bucket[end].date == day) {
      end++;
    }
    return end == low ? const [] : List.unmodifiable(bucket.sublist(low, end));
  }

  @override
  DateTime? get firstDate {
    if (!_firstKnown) {
      _first = _items.isEmpty
          ? null
          : _items.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
      _firstKnown = true;
    }
    return _first;
  }

  @override
  int refundedTotal(String id) {
    final sums = _refunds ??= () {
      final found = <String, int>{};
      for (final e in _items) {
        if (e.refundOf case final of?) found[of] = (found[of] ?? 0) + e.amount;
      }
      return found;
    }();
    return sums[id] ?? 0;
  }

  /// Every month's entries in [inMonth] order, worked out from the list.
  Map<int, List<Entry>> _indexMonths() {
    final groups = <int, List<(int, Entry)>>{};
    for (final (i, e) in _items.indexed) {
      (groups[_monthOf(e)] ??= []).add((i, e));
    }
    final months = <int, List<Entry>>{};
    for (final MapEntry(key: month, value: found) in groups.entries) {
      found.sort((a, b) {
        final byDate = b.$2.date.compareTo(a.$2.date);
        return byDate != 0 ? byDate : b.$1.compareTo(a.$1);
      });
      months[month] = List.unmodifiable([for (final (_, e) in found) e]);
    }
    return months;
  }
}
