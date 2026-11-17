part of 'ledger.dart';

// Entries: adding, changing, removing and bringing them back, a group
// at a time or one by one; each change kept in the data source as one batch.

extension LedgerEntries on Ledger {
  /// Adds [entry], with its receipt photo [receipt] when one is given; a
  /// sale of more shares than are held is refused with a [StateError].
  void add(Entry entry, {String? receipt}) {
    _entries.add(entry);
    _replayOrUndo(() => _entries.removeLast(), trades: entry.isInvestment);
    if (receipt != null) _receipts.set(entry.id, receipt);
    _keep(WriteBatch(entries: [entry], receipts: {entry.id: ?receipt}));
  }

  /// Adds every one of [entries] at once, with the [accounts] and
  /// [categories] they bring, as an import does: all of it is kept
  /// together, or none.
  void addAll(
    List<Entry> entries, {
    List<Account> accounts = const [],
    List<Category> categories = const [],
  }) {
    if (entries.isEmpty && accounts.isEmpty && categories.isEmpty) return;
    final count = _entries.length;
    _entries.addAll(entries);
    _replayOrUndo(
      () => _entries.removeRange(count, _entries.length),
      trades: entries.any((e) => e.isInvestment),
    );
    final seen = <String>{};
    final named = [
      for (final c in categories)
        if (categoryNameFree(c.name) && seen.add(c.name.trim())) c,
    ];
    final ids = {for (final a in _accounts) a.id};
    final opened = [
      for (final a in accounts)
        if (ids.add(a.id)) a,
    ];
    _accounts.addAll(opened);
    _categories.addAll(named);
    notifyListeners();
    _keep(WriteBatch(accounts: opened, categories: named, entries: entries));
  }

  /// Puts [entry] in place of the entry with the same id, with the receipt
  /// photo [receipt] (null takes it away).
  void replace(Entry entry, {String? receipt}) {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index < 0) return add(entry, receipt: receipt);
    final before = _entries[index];
    _entries[index] = entry;
    _replayOrUndo(
      () => _entries[index] = before,
      trades: entry.isInvestment || before.isInvestment,
    );
    final photo = _receipts.set(entry.id, receipt);
    _keep(
      WriteBatch(entries: [entry], receipts: {if (photo) entry.id: receipt}),
    );
  }

  /// Puts each of [entries] in place of the one with the same id, as one
  /// change; those the ledger does not hold are left out.
  void replaceAll(List<Entry> entries) {
    final before = <int, Entry>{};
    for (final e in entries) {
      final index = _entries.indexWhere((x) => x.id == e.id);
      if (index < 0) continue;
      before.putIfAbsent(index, () => _entries[index]);
      _entries[index] = e;
    }
    if (before.isEmpty) return;
    _replayOrUndo(() {
      for (final MapEntry(key: index, value: e) in before.entries) {
        _entries[index] = e;
      }
    }, trades: [...before.values, ...entries].any((e) => e.isInvestment));
    _keep(WriteBatch(entries: [for (final i in before.keys) _entries[i]]));
  }

  /// Puts [entries], written as one, in place of the entries [was] held:
  /// those kept are changed, new ones added and the rest taken away (not
  /// to the trash: they are part of the same change), with the receipt
  /// photo [receipt] on [receiptOn].
  void replaceGroup(
    List<Entry> entries,
    Iterable<String> was, {
    String? receipt,
    String? receiptOn,
  }) {
    final before = List.of(_entries);
    final ids = {for (final e in entries) e.id};
    final gone = {...was}..removeAll(ids);
    _entries.removeWhere((e) => gone.contains(e.id));
    for (final e in entries) {
      final index = _entries.indexWhere((x) => x.id == e.id);
      if (index < 0) {
        _entries.add(e);
      } else {
        _entries[index] = e;
      }
    }
    _replayOrUndo(
      () => _entries
        ..clear()
        ..addAll(before),
      trades: entries.any((e) => e.isInvestment),
    );
    final photos = <String, String?>{};
    for (final id in {...was, ...ids}) {
      final now = id == receiptOn ? receipt : null;
      if (!_receipts.set(id, now)) continue;
      photos[id] = now;
    }
    _keep(
      WriteBatch(
        entries: entries,
        receipts: photos,
        dropped: [for (final id in gone) (Collection.entry, id)],
      ),
    );
  }

  /// Removes the entry with [id] and returns it with its place, for undo.
  /// Null when there is none, or when taking it away would leave a later
  /// sale short of shares: that is told through [problem].
  (int, Entry)? remove(String id) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return null;
    // Its period, worked out while it still counts.
    final skipping = _skipping([_entries[index]]);
    final removed = _entries.removeAt(index);
    if (!_tryReplay(
      () => _entries.insert(index, removed),
      trades: removed.isInvestment,
    )) {
      return null;
    }
    _recurring.replaceExisting(skipping);
    final trashed = Trashed(removed, today);
    _trash.put(trashed);
    _keep(
      WriteBatch(
        trash: [trashed],
        recurring: skipping,
        dropped: [(Collection.entry, removed.id)],
      ),
    );
    if (skipping.isNotEmpty) _changed(const {Topic.recurring});
    return (index, removed);
  }

  /// Removes every entry of [ids] as one change, and returns each with its
  /// place, for undo; none when taking them away would leave a later sale
  /// short of shares, which is told through [problem].
  List<(int, Entry)> removeAll(Iterable<String> ids) {
    final wanted = {...ids};
    final removed = <(int, Entry)>[
      for (final (i, e) in _entries.indexed)
        if (wanted.contains(e.id)) (i, e),
    ];
    if (removed.isEmpty) return const [];
    final skipping = _skipping([for (final (_, e) in removed) e]);
    _entries.removeWhere((e) => wanted.contains(e.id));
    if (!_tryReplay(() {
      for (final (i, e) in removed) {
        _entries.insert(i, e);
      }
    }, trades: removed.any((r) => r.$2.isInvestment))) {
      return const [];
    }
    _recurring.replaceExisting(skipping);
    final trashed = [for (final (_, e) in removed) Trashed(e, today)];
    _trash.putAll(trashed);
    _keep(
      WriteBatch(
        trash: trashed,
        recurring: skipping,
        dropped: [for (final (_, e) in removed) (Collection.entry, e.id)],
      ),
    );
    if (skipping.isNotEmpty) _changed(const {Topic.recurring});
    return removed;
  }

  /// Puts back what [removeAll] took away, as one change.
  bool restoreAll(List<(int, Entry)> removed) {
    if (removed.isEmpty) return true;
    final ids = {for (final (_, e) in removed) e.id};
    if (_entries.any((e) => ids.contains(e.id))) return false;
    for (final (i, e) in removed) {
      _entries.insert(i.clamp(0, _entries.length), e);
    }
    if (!_tryReplay(
      () => _entries.removeWhere((e) => ids.contains(e.id)),
      trades: removed.any((r) => r.$2.isInvestment),
    )) {
      return false;
    }
    _trash.removeEntries(ids);
    final back = _unskipping([for (final (_, e) in removed) e]);
    _recurring.replaceExisting(back);
    _keep(
      WriteBatch(
        entries: [for (final (_, e) in removed) e],
        recurring: back,
        dropped: [for (final id in ids) (Collection.trash, id)],
      ),
    );
    if (back.isNotEmpty) _changed(const {Topic.recurring});
    return true;
  }

  /// Puts back an entry [remove] took away. False, told through
  /// [problem], when it no longer fits the trades kept since.
  bool restore((int, Entry) removed) {
    final (index, entry) = removed;
    if (byId(entry.id) != null) return false;
    _entries.insert(index.clamp(0, _entries.length), entry);
    if (!_tryReplay(() => _entries.remove(entry), trades: entry.isInvestment)) {
      return false;
    }
    _trash.removeEntries({entry.id});
    final back = _unskipping([entry]);
    _recurring.replaceExisting(back);
    _keep(
      WriteBatch(
        entries: [entry],
        recurring: back,
        dropped: [(Collection.trash, entry.id)],
      ),
    );
    if (back.isNotEmpty) _changed(const {Topic.recurring});
    return true;
  }

  /// Puts [trashed] back in the book. False, told through [problem], when
  /// it no longer fits the trades kept since.
  bool restoreTrashed(Trashed trashed) {
    final entry = trashed.entry;
    if (byId(entry.id) != null) {
      // Already back in the book, as by an undo: only the trash keeps it.
      _trash.removeEntries({entry.id});
      _signal();
      _keep(WriteBatch(dropped: [(Collection.trash, entry.id)]));
      return true;
    }
    // An entry written as one with others comes back with them.
    final group = entry.group;
    final back = [
      for (final t in _trash.all)
        if (identical(t, trashed) ||
            (group != null &&
                t.entry.group == group &&
                byId(t.entry.id) == null))
          t,
    ];
    final before = _trash.all;
    _trash.removeAll(back);
    final count = _entries.length;
    _entries.addAll([for (final t in back) t.entry]);
    if (!_tryReplay(() {
      _entries.removeRange(count, _entries.length);
      _trash.replaceWith(before);
    }, trades: back.any((t) => t.entry.isInvestment))) {
      return false;
    }
    final unskipped = _unskipping([for (final t in back) t.entry]);
    _recurring.replaceExisting(unskipped);
    _keep(
      WriteBatch(
        entries: [for (final t in back) t.entry],
        recurring: unskipped,
        dropped: [for (final t in back) (Collection.trash, t.entry.id)],
      ),
    );
    if (unskipped.isNotEmpty) _changed(const {Topic.recurring});
    return true;
  }
}
