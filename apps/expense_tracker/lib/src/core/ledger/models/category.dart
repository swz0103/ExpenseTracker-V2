/// The category every transfer carries.
const transferCategory = '轉帳';

/// Where fees go that have no category of their own, such as a
/// transfer's.
const feeCategory = '其他支出';

final class Category {
  const Category(
    this.name,
    this.icon,
    this.color, {
    this.income = false,
    this.parent,
    this.archived = false,
    this.place,
  });

  /// A name the book has no category for, such as one since deleted:
  /// shown in grey with the plain mark.
  const Category.unknown(this.name)
    : icon = 'other',
      color = 0xFF8C8C80,
      income = false,
      parent = null,
      archived = false,
      place = null;

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
    income: income,
    parent: clearParent ? null : parent ?? this.parent,
    archived: archived ?? this.archived,
    place: place ?? this.place,
  );
}
