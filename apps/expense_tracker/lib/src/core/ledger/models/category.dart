// Exception to ledger words: the starter categories' names are data a
// new book keeps (and renames as it likes), not words the screens say.
import 'package:core/foundation_values.dart' show PublicId;
import 'package:ledger_entries/model.dart' show dividendCategory, feeCategory;

/// The categories a new book starts with, with their marks and colours,
/// each with an id of its own: the one list, which the demo book is
/// seeded with too, so the preview looks as a new book does.
List<Category> starterCategories() => [
  Category('居家生活', 'home', 0xFF5C9A83),
  Category('飲食日常', 'food', 0xFFD08B5B),
  Category('交通通勤', 'travel', 0xFF5B8DB0),
  Category('購物休閒', 'bag', 0xFF8E7CC0),
  Category('訂閱服務', 'subscription', 0xFFC9A34A),
  Category(feeCategory, 'other', 0xFFB07A8C),
  Category('薪資收入', 'salary', 0xFF2F7A65, income: true),
  Category(dividendCategory, 'dividend', 0xFF5A6FA8, income: true),
  Category('其他收入', 'income', 0xFF4E8A9A, income: true),
];

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
