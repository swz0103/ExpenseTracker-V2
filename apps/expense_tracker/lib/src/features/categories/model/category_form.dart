// Exception to models take what they use: the form of a category is the
// page's state; it checks names, places the category and merges or
// archives it, across most of the ledger's category parts (ADR-0013).

import '../../../core/ledger/ledger.dart';

/// What the form of a category holds while it is filled in: a new one,
/// or the changes to [initial]. The name is typed in a field the screen
/// keeps, so it is handed in where it is needed.
final class CategoryForm {
  CategoryForm(this.initial, {this.ledger})
    : icon = initial.icon,
      color = initial.color,
      parent = initial.parent;

  /// The category as the form opened, or a new one with no name.
  final Category initial;

  /// The book, when there is one to check names in and to place the
  /// category under another.
  final Ledger? ledger;

  String icon;

  /// The colour as an ARGB value.
  int color;

  /// The category it sits under; null at the top.
  String? parent;

  /// Whether the category is not kept yet.
  bool get isNew => initial.name.isEmpty;

  /// The book, when the category is kept in it and so may be merged,
  /// archived or given categories under it; null for a new one.
  Ledger? get book => isNew ? null : ledger;

  /// The categories of its side, open ones only.
  List<Category> get _side =>
      ledger?.categories.forEntries(income: initial.income) ?? const [];

  /// The open categories under this one, in their order.
  List<Category> get children => [
    if (!isNew)
      for (final c in _side)
        if (c.parent == initial.name) c,
  ];

  /// The names of the categories it may be put under: those of its side
  /// at the top, itself left out.
  List<String> get parents => [
    for (final c in _side)
      if (c.parent == null && c.name != initial.name) c.name,
  ];

  /// Whether 子分類 is offered: only a kept category at the top has them.
  bool get offersChildren => book != null && initial.parent == null;

  /// Whether 放在哪個分類下 is offered. One level only: a category with
  /// its own subcategories stays on top.
  bool get offersParent =>
      ledger != null && parents.isNotEmpty && children.isEmpty;

  /// Why [name] cannot be saved; null when it can. Categories are found
  /// by name: two with one name would be one.
  String? problemOf(String name) {
    final taken = ledger?.categories.all.any((c) => c.name == name) ?? false;
    if (taken && name != initial.name) {
      return '已經有「$name」這個分類，可以改用合併';
    }
    return null;
  }

  /// The category as the form stands, named [name] (trimmed); null when
  /// it has no name.
  Category? build(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    return Category(
      trimmed,
      icon,
      color,
      income: initial.income,
      parent: parent,
      archived: initial.archived,
      place: initial.place,
    );
  }

  /// A new category under this one, in its icon and the colour chosen.
  Category get newChild => Category(
    '',
    initial.icon,
    color,
    income: initial.income,
    parent: initial.name,
  );
}
