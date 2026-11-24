import '../model/day.dart';
import '../model/ids.dart';

/// A named place owners add things to and the app reads from; the type
/// is the contract every contribution meets. Anyone may declare one: the
/// journal declares [valuers], a screen package may declare its blocks.
final class ContributionPoint<T> {
  const ContributionPoint(this.name);
  final String name;
}

/// Every contribution, by point.
final class Contributions {
  final _items = <ContributionPoint<Object?>, List<(OwnerId, Object?)>>{};

  /// Where an owner adds to [point]: `on(point).add(owner, item)`. Two
  /// steps on purpose: as one generic call, Dart widens the type until a
  /// wrongly shaped item fits, and the mistake shows only when the point
  /// is read. Here the point fixes the type before the item is seen.
  ContributionSlot<T> on<T>(ContributionPoint<T> point) =>
      ContributionSlot._(_items[point] ??= []);

  /// What was added to [point], in the order added.
  List<T> of<T>(ContributionPoint<T> point) => [
    for (final (_, item) in _items[point] ?? const <(OwnerId, Object?)>[])
      item as T,
  ];

  /// What was added to [point], with who added it.
  List<(OwnerId, T)> owned<T>(ContributionPoint<T> point) => [
    for (final (owner, item) in _items[point] ?? const <(OwnerId, Object?)>[])
      (owner, item as T),
  ];
}

/// The place of one point items are added to.
final class ContributionSlot<T> {
  ContributionSlot._(this._items);
  final List<(OwnerId, Object?)> _items;

  void add(OwnerId owner, T item) => _items.add((owner, item));
}

/// What [amount] of [unit] (a currency's minor units, or a quantity of a
/// commodity) is worth in the book's own currency at the end of [asOf];
/// null when this valuer does not know the unit.
typedef Valuer = int? Function(String unit, BigInt amount, Day asOf);

/// Where prices and rates come in, for net worth.
const valuers = ContributionPoint<Valuer>('valuers');
