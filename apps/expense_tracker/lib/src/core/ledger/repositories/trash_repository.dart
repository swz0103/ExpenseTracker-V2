import '../models/models.dart';

/// What the screens may ask of the entries deleted lately.
abstract interface class TrashReader {
  /// The entries deleted lately, the last deleted first; the list cannot
  /// be changed.
  List<Trashed> get all;
}

/// The entries deleted lately (最近刪除), kept to be put back, the last
/// deleted first. The commands that write use it; the screens see a
/// [TrashReader].
final class TrashRepository implements TrashReader {
  TrashRepository([Iterable<Trashed> trashed = const []])
    : _items = [...trashed];

  final List<Trashed> _items;

  @override
  List<Trashed> get all => List.unmodifiable(_items);

  /// Keeps [trashed] as the last deleted.
  void put(Trashed trashed) => _items.insert(0, trashed);

  /// Keeps each of [trashed], deleted in that order, so the last of them
  /// is first.
  void putAll(List<Trashed> trashed) => _items.insertAll(0, trashed.reversed);

  /// Takes away the deleted entries whose ids are in [ids].
  void removeEntries(Set<String> ids) =>
      _items.removeWhere((t) => ids.contains(t.entry.id));

  /// Takes away each of [trashed] (the very ones held).
  void removeAll(Iterable<Trashed> trashed) {
    final gone = Set<Trashed>.identity()..addAll(trashed);
    _items.removeWhere(gone.contains);
  }

  /// Puts what [change] makes of each deleted entry in its place, keeping
  /// when it was deleted; an entry it gives null for is left as it is. For
  /// a rename or a merge, so what comes back fits the book as it is now.
  List<Trashed> changeEntries(Entry? Function(Entry entry) change) {
    final changed = <Trashed>[];
    for (final (i, t) in _items.indexed) {
      final next = change(t.entry);
      if (next != null) changed.add(_items[i] = Trashed(next, t.on));
    }
    return changed;
  }

  /// Whether a deleted entry still names the account [id], so the account
  /// is not removed from under it.
  bool mentionsAccount(String id) =>
      _items.any((t) => t.entry.account == id || t.entry.to == id);

  /// Takes the deleted entries of [trashed], as when the book is read
  /// again or a change is undone.
  void replaceWith(Iterable<Trashed> trashed) {
    final copy = [...trashed];
    _items
      ..clear()
      ..addAll(copy);
  }
}
