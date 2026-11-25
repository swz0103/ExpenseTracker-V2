import 'dart:collection';

import '../models/models.dart';

/// Entries kept in lists by a key (a month, an account, the entry they
/// refund, a group), each list in one order and never changed once handed
/// out: a change puts a new one in its place.
///
/// What changes a list is noted and put in when the list is next asked
/// for, all at once: a change costs the keys it touches, not the length of
/// their lists, and a run of changes (a category renamed on thousands of
/// entries, an account's entries while its balance is not asked for)
/// costs one pass over each list.
final class EntryLists<K> {
  EntryLists(this._lists, this._before);

  /// Each list as made: never changed once made, handed out as a view.
  final Map<K, List<Entry>> _lists;

  /// The view of each list handed out, the same until the list changes.
  final _views = <K, List<Entry>>{};

  /// Whether the first entry comes before the second in a list.
  final bool Function(Entry, Entry) _before;

  final _pending = <K, PendingChanges>{};

  /// The keys that hold, or may hold, a list.
  Iterable<K> get keys => {..._lists.keys, ..._pending.keys};

  /// The list under [key], with what changed in it put in; null when
  /// none is held. It cannot be changed.
  List<Entry>? operator [](K key) {
    _settle(key);
    final list = _lists[key];
    if (list == null) return null;
    return _views[key] ??= UnmodifiableListView(list);
  }

  void _settle(K key) {
    final pending = _pending.remove(key);
    if (pending == null) return;
    final old = _lists[key] ?? const <Entry>[];
    final next =
        pending.now.isEmpty &&
            pending.removed.length <= _few &&
            pending.added.length <= _few
        ? _spliced(old, pending)
        : _merged(old, pending);
    if (identical(next, old)) return;
    _views.remove(key);
    if (next.isEmpty) {
      _lists.remove(key);
    } else {
      _lists[key] = next;
    }
  }

  /// [old] with a few entries taken away and a few added: each found by
  /// a look along the list or a search in its order, the rest copied
  /// across in runs.
  List<Entry> _spliced(List<Entry> old, PendingChanges pending) {
    final gone = [
      for (final e in pending.removed)
        if (old.indexOf(e) case final i when i >= 0) i,
    ]..sort();
    var kept = old;
    if (gone.isNotEmpty) {
      kept = List<Entry>.filled(old.length - gone.length, old.first);
      var from = 0;
      var to = 0;
      for (final i in gone) {
        kept.setRange(to, to + i - from, old, from);
        to += i - from;
        from = i + 1;
      }
      kept.setRange(to, kept.length, old, from);
    }
    if (pending.added.isEmpty) return kept;
    final added = pending.added.toList()
      ..sort((a, b) => _before(a, b) ? -1 : 1);
    final at = [for (final e in added) _placeOf(kept, e)];
    final next = List<Entry>.filled(kept.length + added.length, added.first);
    var from = 0;
    var to = 0;
    for (var k = 0; k < added.length; k++) {
      next.setRange(to, to + at[k] - from, kept, from);
      to += at[k] - from;
      from = at[k];
      next[to++] = added[k];
    }
    next.setRange(to, next.length, kept, from);
    return next;
  }

  /// [old] with every change put in, in one pass.
  List<Entry> _merged(List<Entry> old, PendingChanges pending) {
    final added = pending.added.toList()
      ..sort((a, b) => _before(a, b) ? -1 : 1);
    final next = <Entry>[];
    var k = 0;
    for (final x in old) {
      final y = pending.now[x] ?? x;
      if (pending.removed.contains(y)) continue;
      while (k < added.length && _before(added[k], y)) {
        next.add(added[k++]);
      }
      next.add(y);
    }
    while (k < added.length) {
      next.add(added[k++]);
    }
    return next;
  }

  /// Where [e] would stand in [list]: found by a search.
  int _placeOf(List<Entry> list, Entry e) {
    var low = 0;
    var high = list.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_before(list[middle], e)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// At most this many added to or taken from a list at once are each
  /// found on their own, rather than the list gone through entry by entry.
  static const _few = 8;

  PendingChanges _of(K key) => _pending.putIfAbsent(key, PendingChanges.new);

  /// Puts [now] in [old]'s place under [key].
  void swap(K key, Entry old, Entry now) {
    final pending = _of(key);
    if (pending.added.remove(old)) {
      pending.added.add(now);
      return;
    }
    // [old] may itself have been put there by an earlier swap: then it is
    // that swap's entry that stands in the list.
    final stand = pending.stands.remove(old) ?? old;
    pending.now[stand] = now;
    pending.stands[now] = stand;
  }

  /// Adds [e] under [key], at its place in the order.
  void add(K key, Entry e) => _of(key).added.add(e);

  /// Takes [gone], each held under [key], out of its list.
  void removeAll(K key, List<Entry> gone) {
    final pending = _of(key);
    for (final e in gone) {
      if (!pending.added.remove(e)) pending.removed.add(e);
    }
  }
}

/// What has changed in one list since it was last asked for: entries put
/// in place of others (each now standing for the one in the list, and
/// back), entries added, and entries taken away.
final class PendingChanges {
  final now = Map<Entry, Entry>.identity();
  final stands = Map<Entry, Entry>.identity();
  final added = Set<Entry>.identity();
  final removed = Set<Entry>.identity();
}
