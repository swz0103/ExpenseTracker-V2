// Exception to file length: the entries in the order written and every
// index kept of them (by month, account, id, refund, group, stock) follow each
// change together, one place at a time; apart, each change would be
// told twice and could be followed in one but not the other.
import 'dart:collection';

import '../models/models.dart';
import 'entry_lists.dart';

import 'package:core/time/month_arithmetic.dart';

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

  /// Each month's entries in [inMonth] order, the newest month first:
  /// every entry newest first, a month at a time.
  Iterable<List<Entry>> get newestMonths;

  /// The entries paid from or into [account], in [byDate] order. The list
  /// cannot be changed.
  List<Entry> ofAccount(String account);

  /// The entries written as one under [group], in the order written. The
  /// list cannot be changed.
  List<Entry> inGroup(String group);

  /// The entries of the stock [code] (its trades and dividends), in the
  /// order written. The list cannot be changed, and the same list is
  /// handed out until an entry of [code] changes.
  List<Entry> ofHolding(String code);

  /// Every stock an entry names ([ofHolding]); one whose entries are all
  /// gone may still be among them, with none.
  Iterable<String> get holdingCodes;

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

/// The order every list of entries is shown in, newest first: by day,
/// then the later written first (D76), as [EntryReader.orderOf] keeps it.
/// The one tie-break, whatever the entries' place in memory.
Comparator<Entry> newestFirst(EntryReader book) => (a, b) {
  final byDay = b.date.compareTo(a.date);
  return byDay != 0 ? byDay : book.orderOf(b.id).compareTo(book.orderOf(a.id));
};

/// Every entry of the book, in the order written, with what is asked of
/// them again and again (by month, by account, by id, refunds, groups,
/// stocks) worked out once, on the first ask, and then kept up to date as entries
/// are added, taken away, put in place of another or moved to another
/// day: a change costs the lists it touches (a month, an account), not the
/// whole book. Only a change that cannot be followed cheaply (many entries
/// added at once, the whole list cleared, an entry put in two places)
/// throws the indexes away to be worked out again.
///
/// Each entry has its place in the order written ([orderOf], D75): the
/// list is kept in that order, an entry put back from the trash or by an
/// undo going back to its own place, and where an entry stands among
/// those of its day follows it. The places are held beside the list, one
/// number each ([_orders]), as the book reads them, already in order:
/// nothing is looked up by id to open the book. Entries taken away keep
/// theirs ([_kept]) to come back to.
///
/// A list for the commands that write; the screens see an [EntryReader].
final class EntryRepository implements EntryReader {
  /// [entries] in the order written; [order] gives each its place, as
  /// the book kept it (each in turn when not given).
  EntryRepository([
    Iterable<Entry> entries = const [],
    Map<String, int> order = const {},
  ]) : this._(entries.toList(), null, order);

  /// [entries] with their [places] in the order written, one for each,
  /// as the book reads them: in that order already.
  EntryRepository.placed(List<Entry> entries, List<int> places)
    : this._(entries, places, const {});

  EntryRepository._(
    List<Entry> entries,
    List<int>? places,
    Map<String, int> order,
  ) : _items = [...entries],
      _orders = places == null
          ? [for (final (i, e) in entries.indexed) order[e.id] ?? i]
          : [...places] {
    if (_orders.length != _items.length) {
      throw ArgumentError('${_orders.length} places for ${_items.length}');
    }
    // Kept in the order written: given out of it (a test's book), put in
    // it, those of one place as given.
    var sorted = true;
    for (var i = 1; i < _orders.length && sorted; i++) {
      sorted = _orders[i - 1] <= _orders[i];
    }
    if (!sorted) {
      final at = [for (var i = 0; i < _items.length; i++) i]
        ..sort((a, b) {
          final byPlace = _orders[a].compareTo(_orders[b]);
          return byPlace != 0 ? byPlace : a.compareTo(b);
        });
      final items = [for (final i in at) _items[i]];
      final orders = [for (final i in at) _orders[i]];
      _items
        ..clear()
        ..addAll(items);
      _orders
        ..clear()
        ..addAll(orders);
    }
    _next = _orders.isEmpty ? 0 : _orders.last + 1;
  }

  final List<Entry> _items;

  /// Each entry's place in the order written, beside it in [_items]:
  /// growing along the list.
  final List<int> _orders;

  /// The places of entries taken away, by id, for them to come back to;
  /// and of those the trash holds, as the book opened.
  final _kept = <String, int>{};

  /// The place of the next entry written.
  var _next = 0;

  @override
  int orderOf(String id) {
    final e = byId(id);
    if (e == null) return _kept[id] ?? _next;
    final seqs = _order();
    return seqs != null ? seqs[e]! : _orders[_items.lastIndexOf(e)];
  }

  /// Notes that [place] is taken, as by an entry in the trash, so no entry
  /// written later is put before it; with [id], that it is that entry's,
  /// for it to come back to.
  void reserve(int place, {String? id}) {
    if (place >= _next) _next = place + 1;
    if (id != null) _kept.putIfAbsent(id, () => place);
  }

  /// Puts [entry] back in its place [place] in the order written (D75):
  /// after every entry before it, before every entry after; last when
  /// [place] is null.
  void restoreAt(Entry entry, int? place) {
    if (place == null) return add(entry);
    reserve(place);
    var low = 0;
    var high = _orders.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_orders[middle] < place) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _kept[entry.id] = place;
    insert(low, entry);
  }

  /// Takes the entries of [other] and where each stands, as when the book
  /// is read again.
  void replaceWith(EntryRepository other) {
    _discard();
    _items
      ..clear()
      ..addAll(other._items);
    _orders
      ..clear()
      ..addAll(other._orders);
    _kept
      ..clear()
      ..addAll(other._kept);
    _next = other._next;
  }

  /// More entries added at once than this are not followed one by one.
  static const _followed = 64;

  /// Each entry's place in the order written, to look it up: worked out
  /// from [_orders] when first needed; null until then, and when the list
  /// holds an entry twice (as while a sort moves them).
  Map<Entry, int>? _seqs;

  /// Each month's entries in [inMonth] order.
  EntryLists<int>? _months;

  /// Each account's entries in [byDate] order.
  EntryLists<String>? _accounts;

  /// The entries refunding each entry, by its id, in the order written.
  EntryLists<String>? _refunds;

  /// The entries of each group, in the order written.
  EntryLists<String>? _groups;

  /// The entries of each stock, in the order written.
  EntryLists<String>? _holdings;

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
    _holdings = null;
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
      _groups != null ||
      _holdings != null;

  static int _monthOf(Entry e) => monthIndex(e.date.year, e.date.month);

  /// The accounts [e] is paid from or into, each once.
  static Iterable<String> _accountsOf(Entry e) sync* {
    yield e.account;
    final to = e.to;
    if (to != null && to != e.account) yield to;
  }

  /// [_seqs], worked out from [_orders] when not yet; null when the list
  /// holds an entry twice.
  Map<Entry, int>? _order() {
    final kept = _seqs;
    if (kept != null) return kept;
    final seqs = Map<Entry, int>.identity();
    for (var i = 0; i < _items.length; i++) {
      seqs[_items[i]] = _orders[i];
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
    if (e.holding case final code?) _holdings?.add(code, e);
  }

  /// Notes that [e], now last in the list with its place last in
  /// [_orders], has been added.
  void _noteAdded(Entry e) {
    _touch(e);
    if (_ordered) {
      final seqs = _seqs;
      if (seqs == null || seqs.containsKey(e)) return _discard();
      seqs[e] = _orders.last;
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
      final months = <int, List<Entry>>{};
      final accounts = <String, List<Entry>>{};
      final refunded = <String, List<Entry>>{};
      final groups = <String, List<Entry>>{};
      final stocks = <String, List<Entry>>{};
      for (final e in gone) {
        (months[_monthOf(e)] ??= []).add(e);
        for (final account in _accountsOf(e)) {
          (accounts[account] ??= []).add(e);
        }
        if (e.refundOf case final of?) (refunded[of] ??= []).add(e);
        if (e.group case final group?) (groups[group] ??= []).add(e);
        if (e.holding case final code?) (stocks[code] ??= []).add(e);
      }
      void follow<K>(EntryLists<K>? lists, Map<K, List<Entry>> by) {
        if (lists == null) return;
        for (final MapEntry(:key, :value) in by.entries) {
          lists.removeAll(key, value);
        }
      }

      follow(_months, months);
      follow(_accounts, accounts);
      follow(_refunds, refunded);
      follow(_groups, groups);
      follow(_holdings, stocks);
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

  /// The place of [entry], this very entry; -1 when it is not held.
  /// Looked for from the end, where the entries written lately are, which
  /// are those most often changed.
  int indexOf(Entry entry) => _items.lastIndexOf(entry);

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
    // [entry] takes [old]'s place; another entry's id keeps it to come
    // back to.
    _kept.remove(entry.id);
    if (old.id != entry.id) _kept[old.id] = _orders[index];
    _touch(old);
    _touch(entry);
    if (identical(old, entry)) return;
    if (_ordered) {
      final seqs = _seqs;
      // Already elsewhere in the list, as a sort moves it: two places
      // for one entry, which no place number follows.
      if (seqs == null || seqs.containsKey(entry)) return _discard();
      // At [old]'s place: both numbered while the lists follow.
      seqs[entry] = seqs[old]!;
      _move(old, entry);
      seqs.remove(old);
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
    void follow<K>(EntryLists<K>? lists, Iterable<K> was, Iterable<K> now) {
      if (lists == null) return;
      final staying = {...was}.intersection({...now});
      for (final key in was) {
        if (staying.contains(key) && sameDay) {
          lists.swap(key, old, entry);
        } else {
          lists.removeAll(key, [old]);
        }
      }
      for (final key in now) {
        if (!staying.contains(key) || !sameDay) lists.add(key, entry);
      }
    }

    follow(_months, [_monthOf(old)], [_monthOf(entry)]);
    follow(_accounts, _accountsOf(old), _accountsOf(entry));
    // Kept in the order written only: the same place whatever the day.
    void written(EntryLists<String>? lists, String? was, String? now) {
      if (lists == null) return;
      if (was != null && was == now) return lists.swap(was, old, entry);
      if (was != null) lists.removeAll(was, [old]);
      if (now != null) lists.add(now, entry);
    }

    written(_refunds, old.refundOf, entry.refundOf);
    written(_groups, old.group, entry.group);
    written(_holdings, old.holding, entry.holding);
  }

  /// Adds [element] as the latest written.
  void add(Entry element) {
    _kept.remove(element.id);
    _items.add(element);
    _orders.add(_next++);
    _noteAdded(element);
  }

  void addAll(Iterable<Entry> iterable) {
    final added = iterable.toList();
    if (added.length > _followed) {
      for (final e in added) {
        _kept.remove(e.id);
        _orders.add(_next++);
      }
      _items.addAll(added);
      _discard();
    } else {
      // Each in turn is the last in the list.
      added.forEach(add);
    }
  }

  /// Puts [element] at [index], before the entry there, as an undo puts
  /// back what it took: at the place it kept, or one between its
  /// neighbours'.
  void insert(int index, Entry element) {
    final upper = index < _orders.length ? _orders[index] : null;
    final lower = index > 0 ? _orders[index - 1] : null;
    var place = _kept.remove(element.id);
    var ordered = true;
    if (place == null) {
      if (upper == null) {
        place = _next++;
      } else if ((lower ?? upper - 2) + 1 < upper) {
        place = ((lower ?? upper - 2) + upper) ~/ 2;
      } else {
        // No place left between the two (a new entry put among others, as
        // only a test does): the one after the lower, those after moved
        // on as far as they must be, the indexes worked out again.
        place = lower! + 1;
        ordered = false;
      }
    } else if (place >= _next) {
      _next = place + 1;
    }
    _items.insert(index, element);
    _orders.insert(index, place);
    if (!ordered) {
      for (var j = index + 1; j < _orders.length; j++) {
        if (_orders[j] > _orders[j - 1]) break;
        _orders[j] = _orders[j - 1] + 1;
      }
      if (_orders.last >= _next) _next = _orders.last + 1;
      return _discard();
    }
    _touch(element);
    if (_ordered) {
      final seqs = _seqs;
      if (seqs == null || seqs.containsKey(element)) return _discard();
      seqs[element] = place;
      _place(element);
    }
    _ids?[element.id] = element;
    _noteDay(element.date);
  }

  /// Takes away [element], this very entry; false when it is not held.
  bool remove(Entry element) {
    final index = indexOf(element);
    if (index < 0) return false;
    removeAt(index);
    return true;
  }

  Entry removeAt(int index) {
    final removed = _items.removeAt(index);
    _kept[removed.id] = _orders.removeAt(index);
    _noteRemoved([removed]);
    return removed;
  }

  Entry removeLast() {
    final removed = _items.removeLast();
    _kept[removed.id] = _orders.removeLast();
    _noteRemoved([removed]);
    return removed;
  }

  void removeRange(int start, int end) {
    final gone = _items.sublist(start, end);
    for (var i = start; i < end; i++) {
      _kept[_items[i].id] = _orders[i];
    }
    _items.removeRange(start, end);
    _orders.removeRange(start, end);
    _noteRemoved(gone);
  }

  void removeWhere(bool Function(Entry) test) {
    final gone = <Entry>[];
    var kept = 0;
    for (var i = 0; i < _items.length; i++) {
      final e = _items[i];
      if (test(e)) {
        gone.add(e);
        _kept[e.id] = _orders[i];
      } else {
        _items[kept] = e;
        _orders[kept++] = _orders[i];
      }
    }
    _items.length = kept;
    _orders.length = kept;
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
          if (indexOf(e) case final i when i >= 0) i,
      ]..sort();
      for (final i in at) {
        found.add((i, _items[i]));
        _kept[_items[i].id] = _orders[i];
      }
      for (final i in at.reversed) {
        _items.removeAt(i);
        _orders.removeAt(i);
      }
    } else {
      var kept = 0;
      for (var i = 0; i < _items.length; i++) {
        final e = _items[i];
        if (wanted.contains(e)) {
          found.add((i, e));
          _kept[e.id] = _orders[i];
        } else {
          _items[kept] = e;
          _orders[kept++] = _orders[i];
        }
      }
      _items.length = kept;
      _orders.length = kept;
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
    _orders.clear();
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

  EntryLists<int> get _monthLists => _months ??= _indexMonths();

  @override
  List<Entry> inMonth(int year, int month) =>
      _monthLists[monthIndex(year, month)] ?? const <Entry>[];

  @override
  Iterable<Entry> get byDate sync* {
    final months = _monthLists;
    for (final month in months.keys.toList()..sort()) {
      // A month is kept newest first.
      yield* (months[month] ?? const <Entry>[]).reversed;
    }
  }

  @override
  Iterable<List<Entry>> get newestMonths sync* {
    final months = _monthLists;
    for (final month in months.keys.toList()..sort((a, b) => b - a)) {
      if (months[month] case final entries?) yield entries;
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
        for (final e in (months[month] ?? const <Entry>[]).reversed) {
          for (final account in _accountsOf(e)) {
            (by[account] ??= []).add(e);
          }
        }
      }
      return EntryLists<String>({
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
  List<Entry> ofHolding(String code) =>
      (_holdings ??= _indexWritten((e) => e.holding))[code] ?? const <Entry>[];

  @override
  Iterable<String> get holdingCodes =>
      (_holdings ??= _indexWritten((e) => e.holding)).keys;

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
  EntryLists<String> _indexWritten(String? Function(Entry e) keyOf) {
    _order();
    final found = <String, List<Entry>>{};
    for (final e in _items) {
      if (keyOf(e) case final key?) (found[key] ??= []).add(e);
    }
    return EntryLists({
      for (final MapEntry(:key, :value) in found.entries)
        key: List.unmodifiable(value),
    }, _writtenBefore);
  }

  /// Every month's entries in [inMonth] order, worked out from the list.
  EntryLists<int> _indexMonths() {
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
    return EntryLists(months, _newerThan);
  }
}
