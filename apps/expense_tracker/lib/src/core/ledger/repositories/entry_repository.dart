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

  /// Every entry, the oldest day first and within a day in the order
  /// written: read from the month index, with nothing to sort.
  Iterable<Entry> get byDate;

  /// Each month's entries in [inMonth] order, the newest month first:
  /// every entry newest first, a month at a time.
  Iterable<List<Entry>> get newestMonths;

  /// The entries paid from or into [account], in [byDate] order. The list
  /// cannot be changed.
  List<Entry> ofAccount(String account);

  /// The entries written as one under [group], in the order written. The
  /// list cannot be changed.
  List<Entry> inGroup(String group);

  /// [some] of the entries in the order they were written.
  List<Entry> written(Iterable<Entry> some);

  /// The day of the first entry; null when there is none.
  DateTime? get firstDate;

  /// How much of the entry with [id] has been refunded by entries that
  /// refund it.
  int refundedTotal(String id);

  /// The entries that refund the entry with [id].
  List<Entry> refundsOf(String id);

  /// A number that changes whenever an entry paid from or into [account]
  /// is added, taken away or changed, and whenever the book changes in a
  /// way not followed entry by entry: what was worked out for [account]
  /// alone still holds while it stays the same.
  int versionOf(String account);
}

/// Every entry of the book, in the order written, with what is asked of
/// them again and again (by month, by account, by id, refunds, groups)
/// worked out once, on the first ask, and then kept up to date as entries
/// are added, taken away, put in place of another or moved to another
/// day: a change costs the lists it touches (a month, an account), not the
/// whole book. Only a change that cannot be followed cheaply (many entries
/// added at once, the whole list cleared, an entry put in two places)
/// throws the indexes away to be worked out again.
///
/// Where an entry stands among those of its day is where it is in the
/// list: each is given a place number ([_seqs]) growing along the list,
/// with room between two for one put in between, so an entry can find its
/// place in a month or an account without a pass over the list.
///
/// A list for the commands that write; the screens see an [EntryReader].
final class EntryRepository implements EntryReader {
  EntryRepository([Iterable<Entry> entries = const []]) : _items = [...entries];

  final List<Entry> _items;

  /// More entries added at once than this are not followed one by one.
  static const _followed = 64;

  /// The room between the place numbers of two entries next to each
  /// other when they are first given: so many can be put in between
  /// before the numbers are given again.
  static const _gap = 1 << 10;

  /// Each entry's place number, growing along the list; null until an
  /// ordered index is first worked out, and when the list holds an entry
  /// twice (as while a sort moves them), which no number can follow.
  Map<Entry, int>? _seqs;

  /// Each month's entries in [inMonth] order.
  _Lists<int>? _months;

  /// Each account's entries in [byDate] order.
  _Lists<String>? _accounts;

  /// The entries refunding each entry, by its id, in the order written.
  _Lists<String>? _refunds;

  /// The entries of each group, in the order written.
  _Lists<String>? _groups;

  Map<String, Entry>? _ids;
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
    _seqs = null;
    _months = null;
    _accounts = null;
    _refunds = null;
    _groups = null;
    _ids = null;
    _first = null;
    _firstKnown = false;
  }

  /// Whether place numbers, or an index that keeps the entries in order,
  /// are worked out: a change must then be followed in them.
  bool get _ordered =>
      _seqs != null ||
      _months != null ||
      _accounts != null ||
      _refunds != null ||
      _groups != null;

  static int _monthOf(Entry e) => e.date.year * 12 + e.date.month;

  /// The accounts [e] is paid from or into, each once.
  static Iterable<String> _accountsOf(Entry e) sync* {
    yield e.account;
    final to = e.to;
    if (to != null && to != e.account) yield to;
  }

  /// [_seqs], given from the list when not yet; null when the list holds
  /// an entry twice.
  Map<Entry, int>? _order() {
    final kept = _seqs;
    if (kept != null) return kept;
    final seqs = Map<Entry, int>.identity();
    for (var i = 0; i < _items.length; i++) {
      seqs[_items[i]] = i * _gap;
    }
    if (seqs.length != _items.length) return null;
    return _seqs = seqs;
  }

  int _seqOf(Entry e) => _seqs![e]!;

  /// Newest day first, the last written first within a day.
  bool _newerThan(Entry a, Entry b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate > 0 : _seqOf(a) > _seqOf(b);
  }

  /// Oldest day first, the first written first within a day.
  bool _olderThan(Entry a, Entry b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate < 0 : _seqOf(a) < _seqOf(b);
  }

  bool _writtenBefore(Entry a, Entry b) => _seqOf(a) < _seqOf(b);

  /// Puts [e], whose place number is given, in each ordered index.
  void _place(Entry e) {
    _months?.add(_monthOf(e), e);
    final accounts = _accounts;
    if (accounts != null) {
      for (final account in _accountsOf(e)) {
        accounts.add(account, e);
      }
    }
    if (e.refundOf case final of?) _refunds?.add(of, e);
    if (e.group case final group?) _groups?.add(group, e);
  }

  /// Notes that [e], now last in the list, has been added.
  void _noteAdded(Entry e) {
    _touch(e);
    if (_ordered) {
      final seqs = _seqs;
      if (seqs == null || seqs.containsKey(e)) return _discard();
      final before = _items.length > 1 ? seqs[_items[_items.length - 2]]! : 0;
      seqs[e] = before + _gap;
      _place(e);
    }
    _ids?[e.id] = e;
    _noteDay(e.date);
  }

  /// Notes that an entry on [day] has come.
  void _noteDay(DateTime day) {
    if (!_firstKnown) return;
    final first = _first;
    if (first == null || day.isBefore(first)) _first = day;
  }

  /// Notes that [gone] have been taken out of the list, from wherever
  /// they were.
  void _noteRemoved(List<Entry> gone) {
    if (gone.isEmpty) return;
    gone.forEach(_touch);
    if (_ordered) {
      final seqs = _seqs;
      if (seqs == null) return _discard();
      final set = Set<Entry>.identity()..addAll(gone);
      final months = <int>{};
      final accounts = <String>{};
      final refunded = <String>{};
      final groups = <String>{};
      for (final e in gone) {
        months.add(_monthOf(e));
        accounts.addAll(_accountsOf(e));
        if (e.refundOf case final of?) refunded.add(of);
        if (e.group case final group?) groups.add(group);
      }
      for (final month in months) {
        _months?.removeAll(month, set);
      }
      for (final account in accounts) {
        _accounts?.removeAll(account, set);
      }
      for (final of in refunded) {
        _refunds?.removeAll(of, set);
      }
      for (final group in groups) {
        _groups?.removeAll(group, set);
      }
      gone.forEach(seqs.remove);
    }
    final ids = _ids;
    if (ids != null) {
      for (final e in gone) {
        ids.remove(e.id);
      }
    }
    // The first day may have gone with them.
    if (_firstKnown && gone.any((e) => e.date == _first)) {
      _first = null;
      _firstKnown = false;
    }
  }

  // The list, with every change noticed.

  @override
  bool get isEmpty => _items.isEmpty;

  /// The place of the first entry that passes [test]; -1 when none does.
  int indexWhere(bool Function(Entry entry) test) => _items.indexWhere(test);

  /// Whether any entry passes [test].
  bool any(bool Function(Entry entry) test) => _items.any(test);

  @override
  int get length => _items.length;

  Entry operator [](int index) => _items[index];

  /// Puts [entry] at [index] in place of the entry there: at the same
  /// place among the entries of its day, so a new version of an entry, on
  /// its day or moved to another, is followed in each index.
  void operator []=(int index, Entry entry) {
    final old = _items[index];
    _items[index] = entry;
    _touch(old);
    _touch(entry);
    if (identical(old, entry)) return;
    if (_ordered) {
      final seqs = _seqs;
      // Already elsewhere in the list, as a sort moves it: two places
      // for one entry, which no place number follows.
      if (seqs == null || seqs.containsKey(entry)) return _discard();
      seqs[entry] = seqs.remove(old)!;
      _move(old, entry);
    }
    final ids = _ids;
    if (ids != null) {
      ids.remove(old.id);
      ids[entry.id] = entry;
    }
    if (_firstKnown) {
      final first = _first;
      if (first != null && entry.date.isBefore(first)) {
        _first = entry.date;
      } else if (old.date == first && entry.date != first) {
        _first = null;
        _firstKnown = false;
      }
    }
  }

  /// Follows [entry] put in [old]'s place in the list: in each index,
  /// where it stays under the same key and on the same day, it takes
  /// [old]'s place (put in when that list is next asked for, so a run of
  /// them costs one pass); elsewhere it leaves one list and joins another.
  void _move(Entry old, Entry entry) {
    final sameDay = old.date == entry.date;
    void follow<K>(_Lists<K>? lists, Iterable<K> was, Iterable<K> now) {
      if (lists == null) return;
      final staying = {...was}.intersection({...now});
      for (final key in was) {
        if (staying.contains(key) && sameDay) {
          lists.swap(key, old, entry);
        } else {
          lists.removeAll(key, Set<Entry>.identity()..add(old));
        }
      }
      for (final key in now) {
        if (!staying.contains(key) || !sameDay) lists.add(key, entry);
      }
    }

    follow(_months, [_monthOf(old)], [_monthOf(entry)]);
    follow(_accounts, _accountsOf(old), _accountsOf(entry));
    // Kept in the order written only: the same place whatever the day.
    void written(_Lists<String>? lists, String? was, String? now) {
      if (lists == null) return;
      if (was != null && was == now) return lists.swap(was, old, entry);
      if (was != null) lists.removeAll(was, Set<Entry>.identity()..add(old));
      if (now != null) lists.add(now, entry);
    }

    written(_refunds, old.refundOf, entry.refundOf);
    written(_groups, old.group, entry.group);
  }

  void add(Entry element) {
    _items.add(element);
    _noteAdded(element);
  }

  void addAll(Iterable<Entry> iterable) {
    final added = iterable.toList();
    if (added.length > _followed) {
      _items.addAll(added);
      _discard();
    } else {
      // Each in turn is the last in the list.
      for (final e in added) {
        _items.add(e);
        _noteAdded(e);
      }
    }
  }

  /// Puts [element] at [index], before the entry there: given a place
  /// number between its neighbours'.
  void insert(int index, Entry element) {
    if (index >= _items.length) return add(element);
    _items.insert(index, element);
    _touch(element);
    if (_ordered) {
      final seqs = _seqs;
      if (seqs == null || seqs.containsKey(element)) return _discard();
      final upper = seqs[_items[index + 1]]!;
      final lower = index > 0 ? seqs[_items[index - 1]]! : upper - 2 * _gap;
      // No room left between the two: numbered afresh when next asked.
      if (upper - lower < 2) return _discard();
      seqs[element] = lower + (upper - lower) ~/ 2;
      _place(element);
    }
    _ids?[element.id] = element;
    _noteDay(element.date);
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
    _noteRemoved([removed]);
    return removed;
  }

  Entry removeLast() {
    final removed = _items.removeLast();
    _noteRemoved([removed]);
    return removed;
  }

  void removeRange(int start, int end) {
    final gone = _items.sublist(start, end);
    _items.removeRange(start, end);
    _noteRemoved(gone);
  }

  void removeWhere(bool Function(Entry) test) {
    final gone = <Entry>[];
    _items.removeWhere((e) {
      if (!test(e)) return false;
      gone.add(e);
      return true;
    });
    _noteRemoved(gone);
  }

  /// Takes away each of [gone], these very entries, and returns where
  /// each stood before, in the order of the list: for putting them back
  /// with [insert], the first first. Those not held are passed over.
  List<(int, Entry)> removeEach(Iterable<Entry> gone) {
    final wanted = Set<Entry>.identity()..addAll(gone);
    final found = <(int, Entry)>[];
    if (wanted.isEmpty) return found;
    if (wanted.length <= _few) {
      // A few: each found by a plain look along the list.
      final at = [
        for (final e in wanted)
          if (_items.indexOf(e) case final i when i >= 0) i,
      ]..sort();
      for (final i in at) {
        found.add((i, _items[i]));
      }
      for (final i in at.reversed) {
        _items.removeAt(i);
      }
    } else {
      var kept = 0;
      for (var i = 0; i < _items.length; i++) {
        final e = _items[i];
        if (wanted.contains(e)) {
          found.add((i, e));
        } else {
          _items[kept++] = e;
        }
      }
      _items.length = kept;
    }
    _noteRemoved([for (final (_, e) in found) e]);
    return found;
  }

  /// At most this many entries taken away together are each looked for
  /// along the list, rather than the list gone through once.
  static const _few = 8;

  void clear() {
    _discard();
    _items.clear();
  }

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

  _Lists<int> get _monthLists => _months ??= _indexMonths();

  @override
  List<Entry> inMonth(int year, int month) =>
      _monthLists[year * 12 + month] ?? const <Entry>[];

  @override
  Iterable<Entry> get byDate sync* {
    final months = _monthLists;
    for (final month in months.keys.toList()..sort()) {
      // A month is kept newest first.
      yield* months[month]!.reversed;
    }
  }

  @override
  Iterable<List<Entry>> get newestMonths sync* {
    final months = _monthLists;
    for (final month in months.keys.toList()..sort((a, b) => b - a)) {
      yield months[month]!;
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
  List<Entry> ofAccount(String account) {
    final accounts = _accounts ??= () {
      final months = _monthLists;
      final by = <String, List<Entry>>{};
      for (final month in months.keys.toList()..sort()) {
        for (final e in months[month]!.reversed) {
          for (final account in _accountsOf(e)) {
            (by[account] ??= []).add(e);
          }
        }
      }
      return _Lists<String>({
        for (final MapEntry(:key, :value) in by.entries)
          key: List.unmodifiable(value),
      }, _olderThan);
    }();
    return accounts[account] ?? const <Entry>[];
  }

  @override
  List<Entry> inGroup(String group) =>
      (_groups ??= _indexWritten((e) => e.group))[group] ?? const <Entry>[];

  @override
  List<Entry> written(Iterable<Entry> some) {
    final seqs = _order();
    if (seqs == null) {
      final wanted = Set<Entry>.identity()..addAll(some);
      return [
        for (final e in _items)
          if (wanted.contains(e)) e,
      ];
    }
    return [
      for (final e in some)
        if (seqs.containsKey(e)) e,
    ]..sort((a, b) => seqs[a]!.compareTo(seqs[b]!));
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
  int refundedTotal(String id) =>
      refundsOf(id).fold(0, (sum, e) => sum + e.amount);

  @override
  List<Entry> refundsOf(String id) =>
      (_refunds ??= _indexWritten((e) => e.refundOf))[id] ?? const <Entry>[];

  /// The entries under each key [keyOf] gives, in the order written.
  _Lists<String> _indexWritten(String? Function(Entry e) keyOf) {
    _order();
    final found = <String, List<Entry>>{};
    for (final e in _items) {
      if (keyOf(e) case final key?) (found[key] ??= []).add(e);
    }
    return _Lists({
      for (final MapEntry(:key, :value) in found.entries)
        key: List.unmodifiable(value),
    }, _writtenBefore);
  }

  /// Every month's entries in [inMonth] order, worked out from the list.
  _Lists<int> _indexMonths() {
    _order();
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
    return _Lists(months, _newerThan);
  }
}

/// Entries kept in lists by a key (a month, an account, the entry they
/// refund, a group), each list in one order and never changed once handed
/// out: a change puts a new one in its place.
final class _Lists<K> {
  _Lists(this._lists, this._before);

  final Map<K, List<Entry>> _lists;

  /// Whether the first entry comes before the second in a list.
  final bool Function(Entry, Entry) _before;

  /// Entries put in place of others at the same place, not yet in their
  /// lists: a run of them (a category renamed on thousands of entries)
  /// costs one pass over a list when it is next asked for, not one each.
  final _pending = <K, _Swaps>{};

  Iterable<K> get keys => _lists.keys;

  /// The list under [key], with what was put in place in it.
  List<Entry>? operator [](K key) {
    _settle(key);
    return _lists[key];
  }

  void _settle(K key) {
    final swaps = _pending.remove(key);
    if (swaps == null) return;
    final list = _lists[key];
    if (list == null) return;
    _lists[key] = List.unmodifiable([for (final x in list) swaps.now[x] ?? x]);
  }

  /// Puts [now] in [old]'s place under [key].
  void swap(K key, Entry old, Entry now) {
    final swaps = _pending.putIfAbsent(key, _Swaps.new);
    // [old] may itself have been put there by an earlier swap: then it is
    // that swap's entry that stands in the list.
    final stand = swaps.stands.remove(old) ?? old;
    swaps.now[stand] = now;
    swaps.stands[now] = stand;
  }

  /// Adds [e] under [key], at its place in the order.
  void add(K key, Entry e) {
    _settle(key);
    final old = _lists[key] ?? const <Entry>[];
    var low = 0;
    var high = old.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_before(old[middle], e)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _lists[key] = List.unmodifiable([
      ...old.take(low),
      e,
      ...old.skip(low),
    ]);
  }

  /// Takes [gone] out of the list under [key].
  void removeAll(K key, Set<Entry> gone) {
    _settle(key);
    final old = _lists[key];
    if (old == null) return;
    final kept = [
      for (final x in old)
        if (!gone.contains(x)) x,
    ];
    if (kept.isEmpty) {
      _lists.remove(key);
    } else if (kept.length != old.length) {
      _lists[key] = List.unmodifiable(kept);
    }
  }
}

/// The entries put in place of others in one list: each now standing for
/// the one in the list, and back.
final class _Swaps {
  final now = Map<Entry, Entry>.identity();
  final stands = Map<Entry, Entry>.identity();
}
