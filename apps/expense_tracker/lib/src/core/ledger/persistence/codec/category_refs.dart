import '../../models/category.dart';

/// Which category an id stands for. Records are kept under a category's id,
/// which never changes, and shown under its name, which can: so a category
/// renamed is one row written, not every entry that carries it.
///
/// A name no category has (an entry that still carries one since deleted)
/// has no id and is kept as the name it is.
final class CategoryRefs {
  CategoryRefs([Iterable<Category> categories = const []]) {
    categories.forEach(set);
  }

  final _names = <String, String>{};
  final _ids = <String, String>{};

  /// The id of the category named [name]; null when there is none.
  String? idOf(String name) => _ids[name];

  /// The name of the category with [id]; the id itself when there is none,
  /// so what cannot be placed is still shown.
  String nameOf(String id) => _names[id] ?? id;

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

/// The collections whose records name a category, as kept on disk.
const namingCollections = ['category', 'entry', 'budget', 'recurring', 'trash'];

/// [json], a record of [collection] as kept, with each category it names
/// by a name [idOf] knows named by that id instead; null when it names
/// none so. Every other field, known to this version or not, is kept.
///
/// A record names a category by name only while no category has that
/// name; once one has, the record names it by its id, so a rename is one
/// row written and reaches every record (see [CategoryRefs]).
Map<String, Object?>? namesToIds(
  String collection,
  Map<String, Object?> json,
  String? Function(String name) idOf,
) => switch (collection) {
  'entry' => _entryIds(json, idOf),
  'trash' => switch (json['entry']) {
    final Map<String, Object?> entry => switch (_entryIds(entry, idOf)) {
      null => null,
      final next => {...json, 'entry': next},
    },
    _ => null,
  },
  'category' => _byId(json, 'parent', 'parentId', idOf),
  'budget' || 'recurring' => _byId(json, 'category', 'categoryId', idOf),
  _ => null,
};

/// [json] with the category named under [key] named by its id under
/// [idKey]; null when none is named, it is by id already, or [idOf] does
/// not know the name.
Map<String, Object?>? _byId(
  Map<String, Object?> json,
  String key,
  String idKey,
  String? Function(String name) idOf,
) {
  final name = json[key];
  if (name is! String || json[idKey] != null) return null;
  final id = idOf(name);
  if (id == null) return null;
  return {...json, idKey: id}..remove(key);
}

/// An entry's category and each part's, by id where [idOf] knows them.
Map<String, Object?>? _entryIds(
  Map<String, Object?> json,
  String? Function(String name) idOf,
) {
  var next = _byId(json, 'category', 'categoryId', idOf);
  final parts = json['parts'];
  if (parts is! List<Object?>) return next;
  var moved = false;
  final named = <Object?>[];
  for (final part in parts) {
    final byId = part is Map<String, Object?>
        ? _byId(part, 'name', 'categoryId', idOf)
        : null;
    if (byId != null) moved = true;
    named.add(byId ?? part);
  }
  if (moved) next = {...next ?? json, 'parts': named};
  return next;
}
