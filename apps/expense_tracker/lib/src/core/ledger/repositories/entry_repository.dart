import 'dart:collection';

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
/// once and thrown away by any change of the entries.
///
/// A list for the commands that write; the screens see an [EntryReader].
final class EntryRepository extends ListBase<Entry> implements EntryReader {
  EntryRepository([Iterable<Entry> entries = const []]) : _items = [...entries];

  final List<Entry> _items;

  Map<int, List<Entry>>? _months;
  Map<DateTime, List<Entry>>? _days;
  Map<String, Entry>? _ids;
  Map<String, int>? _refunds;
  DateTime? _first;
  var _firstKnown = false;

  void _changed() {
    _months = null;
    _days = null;
    _ids = null;
    _refunds = null;
    _first = null;
    _firstKnown = false;
  }

  // The list, with every change noticed.

  @override
  int get length => _items.length;

  @override
  set length(int newLength) {
    _changed();
    _items.length = newLength;
  }

  @override
  Entry operator [](int index) => _items[index];

  @override
  void operator []=(int index, Entry entry) {
    _changed();
    _items[index] = entry;
  }

  @override
  void add(Entry element) {
    _changed();
    _items.add(element);
  }

  @override
  void addAll(Iterable<Entry> iterable) {
    _changed();
    _items.addAll(iterable);
  }

  @override
  void insert(int index, Entry element) {
    _changed();
    _items.insert(index, element);
  }

  @override
  bool remove(Object? element) {
    _changed();
    return _items.remove(element);
  }

  @override
  Entry removeAt(int index) {
    _changed();
    return _items.removeAt(index);
  }

  @override
  Entry removeLast() {
    _changed();
    return _items.removeLast();
  }

  @override
  void removeRange(int start, int end) {
    _changed();
    _items.removeRange(start, end);
  }

  @override
  void removeWhere(bool Function(Entry) test) {
    _changed();
    _items.removeWhere(test);
  }

  @override
  void clear() {
    _changed();
    _items.clear();
  }

  // What is asked of them.

  @override
  List<Entry> get all => UnmodifiableListView(_items);

  @override
  Entry? byId(String id) => (_ids ??= {for (final e in _items) e.id: e})[id];

  @override
  List<Entry> inMonth(int year, int month) =>
      (_months ??= _indexMonths())[year * 12 + month] ?? const <Entry>[];

  @override
  List<Entry> onDay(DateTime day) => (_days ??= _indexDays())[day] ?? const [];

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

  /// Every month's entries in [inMonth] order, built once per change.
  Map<int, List<Entry>> _indexMonths() {
    final groups = <int, List<(int, Entry)>>{};
    for (final (i, e) in _items.indexed) {
      (groups[e.date.year * 12 + e.date.month] ??= []).add((i, e));
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

  /// Every day's entries in [inMonth] order, built once per change.
  Map<DateTime, List<Entry>> _indexDays() {
    final days = <DateTime, List<Entry>>{};
    for (final month in (_months ??= _indexMonths()).values) {
      for (final e in month) {
        (days[e.date] ??= []).add(e);
      }
    }
    return days;
  }
}
