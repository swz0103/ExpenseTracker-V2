import 'dart:collection';
import 'dart:math' show Random;

import '../models/models.dart';

/// What the screens and queries may ask of the entries: no way to change
/// them.
abstract interface class EntryReader {
  /// Every entry in the order written; the list cannot be changed.
  List<Entry> get all;

  int get length;

  bool get isEmpty;

  /// The entry with [id], if it is still in the book.
  Entry? byId(String id);

  /// Entries in [year]/[month], newest day first; within a day the most
  /// recently recorded first. The list cannot be changed.
  List<Entry> inMonth(int year, int month);

  /// Entries on [day], in [inMonth] order.
  List<Entry> onDay(DateTime day);

  /// The day of the first entry; null when there is none.
  DateTime? get firstDate;

  /// How much of the entry with [id] has been refunded by entries that
  /// refund it.
  int refundedTotal(String id);
}

/// Every entry of the book, in the order written, with what is asked of
/// them again and again (by month, by day, by id, refunds) worked out
/// once, on the first ask, and then kept up to date as entries are added,
/// taken away or put in place of another: a change costs the entries of
/// one month, not of the whole book. A change that cannot be followed
/// cheaply (one in the middle of the list, many at once, an entry moved to
/// another day) throws the indexes away to be worked out again.
///
/// A list for the commands that write; the screens see an [EntryReader].
final class EntryRepository extends ListBase<Entry> implements EntryReader {
  EntryRepository([Iterable<Entry> entries = const []]) : _items = [...entries];

  final List<Entry> _items;

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

  void _discard() {
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
  int get length => _items.length;

  @override
  set length(int newLength) {
    _discard();
    _items.length = newLength;
  }

  @override
  Entry operator [](int index) => _items[index];

  @override
  void operator []=(int index, Entry entry) {
    final old = _items[index];
    _items[index] = entry;
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

  @override
  void add(Entry element) {
    _items.add(element);
    _noteAdded(element);
  }

  @override
  void addAll(Iterable<Entry> iterable) {
    final added = iterable.toList();
    _items.addAll(added);
    if (added.length > _followed) {
      _discard();
    } else {
      added.forEach(_noteAdded);
    }
  }

  @override
  void insert(int index, Entry element) {
    if (index >= _items.length) return add(element);
    _discard();
    _items.insert(index, element);
  }

  @override
  bool remove(Object? element) {
    final index = element is Entry ? _items.indexOf(element) : -1;
    if (index < 0) return false;
    removeAt(index);
    return true;
  }

  @override
  Entry removeAt(int index) {
    final removed = _items.removeAt(index);
    _noteRemoved(removed);
    return removed;
  }

  @override
  Entry removeLast() {
    final removed = _items.removeLast();
    _noteRemoved(removed);
    return removed;
  }

  @override
  void removeRange(int start, int end) {
    _discard();
    _items.removeRange(start, end);
  }

  @override
  void removeWhere(bool Function(Entry) test) {
    _discard();
    _items.removeWhere(test);
  }

  @override
  void clear() {
    _discard();
    _items.clear();
  }

  // The rest of what a list can do, each a change that cannot be followed
  // one entry at a time: done on the list itself, the indexes thrown away.

  @override
  void insertAll(int index, Iterable<Entry> iterable) {
    _discard();
    _items.insertAll(index, iterable);
  }

  @override
  void setRange(
    int start,
    int end,
    Iterable<Entry> iterable, [
    int skipCount = 0,
  ]) {
    _discard();
    _items.setRange(start, end, iterable, skipCount);
  }

  @override
  void setAll(int index, Iterable<Entry> iterable) {
    _discard();
    _items.setAll(index, iterable);
  }

  @override
  void replaceRange(int start, int end, Iterable<Entry> newContents) {
    _discard();
    _items.replaceRange(start, end, newContents);
  }

  @override
  void fillRange(int start, int end, [Entry? fill]) {
    _discard();
    _items.fillRange(start, end, fill);
  }

  @override
  void retainWhere(bool Function(Entry) test) {
    _discard();
    _items.retainWhere(test);
  }

  @override
  void sort([int Function(Entry a, Entry b)? compare]) {
    _discard();
    _items.sort(compare);
  }

  @override
  void shuffle([Random? random]) {
    _discard();
    _items.shuffle(random);
  }

  // What is asked of them.

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
