import 'package:core/foundation_values.dart' show PublicId;

final class Category {
  /// A new category has an [id] of its own unless it is given one, as when
  /// it is read back.
  Category(
    this.name,
    this.icon,
    this.color, {
    String? id,
    this.income = false,
    this.parent,
    this.archived = false,
    this.place,
  }) : id = id ?? PublicId.generate().value;

  /// A name the book has no category for, such as one since deleted:
  /// shown in grey with the plain mark.
  ///
  /// It has no id and is never kept.
  const Category.unknown(this.name)
    : id = '',
      icon = 'other',
      color = 0xFF8C8C80,
      income = false,
      parent = null,
      archived = false,
      place = null;

  /// What the category is known by for good: a name can change, an id does
  /// not. Entries, budgets and recurring items are kept under it.
  final String id;

  final String name;

  /// A key into the app's icon set, such as `food`.
  final String icon;

  /// Its colour as ARGB, as the user picked it; the look softens it on
  /// the dark theme when painting.
  final int color;
  final bool income;

  /// The category this one sits under, if any.
  final String? parent;

  /// No longer offered for new entries; its history stays.
  final bool archived;

  /// Where it stands on 分類 and in the composer's row, as dragged there;
  /// null for one never moved, which follows the placed ones.
  final int? place;

  /// This category under another [id]: the one an edited copy built
  /// afresh must keep, to stay the same category.
  Category withId(String id) => Category(
    name,
    icon,
    color,
    id: id,
    income: income,
    parent: parent,
    archived: archived,
    place: place,
  );

  Category copyWith({
    String? name,
    String? parent,
    bool clearParent = false,
    bool? archived,
    int? place,
  }) => Category(
    name ?? this.name,
    icon,
    color,
    id: id,
    income: income,
    parent: clearParent ? null : parent ?? this.parent,
    archived: archived ?? this.archived,
    place: place ?? this.place,
  );
}
