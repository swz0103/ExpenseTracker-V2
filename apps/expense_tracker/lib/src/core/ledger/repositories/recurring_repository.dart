import '../models/models.dart';

/// What the screens and queries may ask of the recurring items.
abstract interface class RecurringReader {
  /// Every recurring item, in the order added; the list cannot be changed.
  List<Recurring> get all;

  /// The recurring item with [id]; null when there is none.
  Recurring? byId(String id);
}

/// The book's recurring items (定期交易): rent, subscriptions, salary.
/// The commands that write use it; the screens see a [RecurringReader].
final class RecurringRepository implements RecurringReader {
  RecurringRepository([Iterable<Recurring> items = const []])
    : _items = [...items];

  final List<Recurring> _items;

  @override
  List<Recurring> get all => List.unmodifiable(_items);

  @override
  Recurring? byId(String id) {
    for (final r in _items) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Puts [item] in place of the one with its id, or adds it at the end.
  void put(Recurring item) {
    final index = _items.indexWhere((r) => r.id == item.id);
    if (index < 0) {
      _items.add(item);
    } else {
      _items[index] = item;
    }
  }

  /// Puts each of [items] in place of the one with its id; one the book no
  /// longer holds is left out, not added.
  void replaceExisting(Iterable<Recurring> items) {
    for (final item in items) {
      final index = _items.indexWhere((r) => r.id == item.id);
      if (index >= 0) _items[index] = item;
    }
  }

  /// Takes away the item with [id] and returns it; null when there is none.
  Recurring? remove(String id) {
    final index = _items.indexWhere((r) => r.id == id);
    return index < 0 ? null : _items.removeAt(index);
  }

  /// Moves the items of category [from] to [to].
  List<Recurring> renameCategory(String from, String to) {
    final changed = <Recurring>[];
    for (final (i, r) in _items.indexed) {
      if (r.category == from) changed.add(_items[i] = r.copyWith(category: to));
    }
    return changed;
  }

  /// Whether an item is paid from or into the account [id].
  bool mentionsAccount(String id) => _items.any((r) => r.account == id);

  /// Takes the items of [items], as when the book is read again.
  void replaceWith(Iterable<Recurring> items) {
    final copy = [...items];
    _items
      ..clear()
      ..addAll(copy);
  }
}
