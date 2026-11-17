import '../models/models.dart';

/// What the screens and queries may ask of the categories.
abstract interface class CategoryReader {
  /// Every category, the placed ones first by place, then the others in
  /// the order they came; the list cannot be changed.
  List<Category> get all;

  /// The category named [name]; one with no id, shown in grey, when the
  /// book has none of that name (such as one since deleted).
  Category byName(String name);

  /// The categories offered for new entries of the kind: open ones.
  List<Category> forEntries({required bool income});

  /// Whether [name] can be a category's: not empty, not a name the book
  /// keeps for itself (all spending, transfers, a `#` tag budget) and not
  /// taken, unless by [except].
  bool isNameFree(String name, {String? except});
}

/// The book's categories, in the order shown, with an index by name. The
/// commands that write use it; the screens see a [CategoryReader].
final class CategoryRepository implements CategoryReader {
  CategoryRepository([Iterable<Category> categories = const []])
    : _items = placed(categories);

  final List<Category> _items;
  Map<String, Category>? _byName;

  void _changed() => _byName = null;

  /// [categories] with the placed ones first, by place, then the others
  /// in the order they came.
  static List<Category> placed(Iterable<Category> categories) {
    final indexed = [...categories.indexed];
    indexed.sort((a, b) {
      final (pa, pb) = (a.$2.place, b.$2.place);
      if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
      if (pa != null && pb == null) return -1;
      if (pa == null && pb != null) return 1;
      return a.$1.compareTo(b.$1);
    });
    return [for (final (_, c) in indexed) c];
  }

  @override
  List<Category> get all => List.unmodifiable(_items);

  @override
  Category byName(String name) =>
      (_byName ??= {for (final c in _items) c.name: c})[name] ??
      Category.unknown(name);

  @override
  List<Category> forEntries({required bool income}) => [
    for (final c in _items)
      if (c.income == income && !c.archived) c,
  ];

  @override
  bool isNameFree(String name, {String? except}) {
    final trimmed = name.trim();
    // A category keeps its own name, even one from before these rules.
    if (except != null && trimmed == except) return true;
    if (trimmed.isEmpty ||
        trimmed == allSpending ||
        trimmed == transferCategory ||
        trimmed.startsWith('#')) {
      return false;
    }
    return !_items.any((c) => c.name == trimmed);
  }

  /// Adds [category] last; its name is checked by the caller.
  void add(Category category) {
    _items.add(category);
    _changed();
  }

  /// Adds each of [categories] last, in order.
  void addAll(Iterable<Category> categories) {
    _items.addAll(categories);
    _changed();
  }

  /// Gives the categories of [names] those places, in that order, as
  /// dragged on 分類, and returns those whose place changed; the others
  /// keep theirs after them.
  List<Category> place(List<String> names) {
    final moved = <Category>[];
    for (final (place, name) in names.indexed) {
      final index = _items.indexWhere((c) => c.name == name);
      if (index < 0 || _items[index].place == place) continue;
      _items[index] = _items[index].copyWith(place: place);
      moved.add(_items[index]);
    }
    if (moved.isEmpty) return moved;
    final sorted = placed(_items);
    _items
      ..clear()
      ..addAll(sorted);
    _changed();
    return moved;
  }

  /// Puts [updated] in place of the category named [name], keeping its id
  /// and, when [updated] has none, the place it was dragged to; returns
  /// what is kept, or null when there is no such category.
  Category? replace(String name, Category updated) {
    final index = _items.indexWhere((c) => c.name == name);
    if (index < 0) return null;
    final kept = _items[index];
    final next = updated.withId(kept.id);
    _items[index] = next.place == null
        ? next.copyWith(place: kept.place)
        : next;
    _changed();
    return _items[index];
  }

  /// Renames [from] to [to], the category and the parent of those under
  /// it.
  void rename(String from, String to) {
    for (final (i, c) in _items.indexed) {
      if (c.name == from) _items[i] = c.copyWith(name: to);
      if (c.parent == from) _items[i] = _items[i].copyWith(parent: to);
    }
    _changed();
  }

  /// Takes away [name], whose entries went elsewhere; those under it are
  /// no longer under anything.
  void removeMerged(String name) {
    _items.removeWhere((c) => c.name == name);
    for (final (i, c) in _items.indexed) {
      if (c.parent == name) _items[i] = c.copyWith(clearParent: true);
    }
    _changed();
  }

  /// Takes the categories of [categories], in their order, as when the
  /// book is read again.
  void replaceWith(Iterable<Category> categories) {
    final copy = [...categories];
    _items
      ..clear()
      ..addAll(copy);
    _changed();
  }
}
