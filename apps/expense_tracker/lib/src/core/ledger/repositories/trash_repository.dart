import '../models/models.dart';

/// What the screens may ask of the entries deleted lately.
abstract interface class TrashReader {
  /// The entries deleted lately, the last day one was deleted first, and
  /// within a day the latest written first ([trashOrder]); the list
  /// cannot be changed.
  List<Trashed> get all;
}

/// The order of the trash: by the day deleted, the latest first, then by
/// the entries' order written, the latest first. What the trash holds
/// and what the book keeps of it read alike, as each keeps both.
int trashOrder(Trashed a, Trashed b) {
  final byDay = b.on.compareTo(a.on);
  if (byDay != 0) return byDay;
  return (b.order ?? -1).compareTo(a.order ?? -1);
}

/// The entries deleted lately (最近刪除), kept to be put back, the last
/// deleted first. The commands that write use it; the screens see a
/// [TrashReader].
final class TrashRepository implements TrashReader {
  TrashRepository([Iterable<Trashed> trashed = const []])
    : _items = [...trashed]..sort(trashOrder);

  final List<Trashed> _items;

  @override
  List<Trashed> get all => List.unmodifiable(_items);

  /// Keeps [trashed], in its place ([trashOrder]).
  void put(Trashed trashed) => putAll([trashed]);

  /// Keeps each of [trashed], each in its place ([trashOrder]).
  void putAll(List<Trashed> trashed) => _items
    ..addAll(trashed)
    ..sort(trashOrder);

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
      if (next != null) {
        changed.add(_items[i] = Trashed(next, t.on, order: t.order));
      }
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
      ..addAll(copy)
      ..sort(trashOrder);
  }
}
