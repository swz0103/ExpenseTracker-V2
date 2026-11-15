import '../../models/category.dart';

/// Which category an id stands for. Records are kept under a category's id,
/// which never changes, and shown under its name, which can: so a category
/// renamed is one row written, not every entry that carries it.
///
/// A name no category has (an entry that still carries one since deleted)
/// has no id and is kept as the name it is.
final class CategoryRefs {
  CategoryRefs([Iterable<Category> categories = const []]) : _lenient = false {
    categories.forEach(set);
  }

  /// Refs that take every id for its own name, for reading a row out of
  /// context, as a backup is checked before it is restored.
  CategoryRefs.lenient() : _lenient = true;

  final _names = <String, String>{};
  final _ids = <String, String>{};
  final bool _lenient;

  /// The id of the category named [name]; null when there is none.
  String? idOf(String name) => _ids[name];

  /// The name of the category with [id]; the id itself when there is none,
  /// so what cannot be placed is still shown.
  String nameOf(String id) => _names[id] ?? id;

  /// Whether a category with [id] is known.
  bool knows(String id) => _lenient || _names.containsKey(id);

  /// Puts [category] in, or renames the one with its id.
  void set(Category category) {
    final old = _names[category.id];
    if (old != null) _ids.remove(old);
    _names[category.id] = category.name;
    _ids[category.name] = category.id;
  }

  /// Starts again from [pairs] of an id and the name it stands for, as read
  /// from the stored rows, before any category is built.
  void fill(Iterable<(String, String)> pairs) {
    _names.clear();
    _ids.clear();
    for (final (id, name) in pairs) {
      _names[id] = name;
      _ids[name] = id;
    }
  }

  /// Takes the category with [id] out.
  void remove(String id) {
    final name = _names.remove(id);
    if (name != null) _ids.remove(name);
  }
}
