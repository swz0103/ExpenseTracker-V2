import 'package:core/foundation_values.dart' show Currency, Money;

import '../model/entry.dart';

/// What a refund gives back of the spending it refunds: its worth in
/// NT$, its split by category and its tags.
typedef RefundShare = ({
  /// The refund's worth in whole NT$, for a purchase that has one ([Entry
  /// .home]); null otherwise.
  int? home,

  /// The refund's amount by category, as the purchase's split; empty
  /// when the purchase was not split.
  List<(String, int)> parts,

  /// The category the refund is kept under: the first part's, else the
  /// purchase's.
  String category,

  /// The purchase's tags: a tag's total gives back what it counted.
  List<String> tags,
});

/// What a refund of [amount] gives back of [original], [earlier] being
/// the refunds of it already kept (the one being changed left out): the
/// share of what is still unrefunded, of its worth in NT$ (D62) and of
/// each part of its split (D65), so the refund that gives back the rest
/// takes exactly the rest and a purchase refunded in full leaves nothing
/// behind in any category, tag or month. A worth is rounded once, half
/// away from zero (core's `Money.quantizeRatio`); the parts are shared by
/// the largest remainder (core's `Money.allocate`), so they add up to
/// [amount] and none gives back more than its part has left. One rule
/// for every refund, written from the composer or read from a file.
RefundShare refundShare(
  Entry original,
  int amount, {
  Iterable<Entry> earlier = const [],
}) {
  var amountLeft = original.amount;
  int? homeLeft = original.home;
  final partsLeft = <String, int>{
    for (final (name, value) in original.parts) name: value,
  };
  for (final e in earlier) {
    amountLeft -= e.amount;
    if (homeLeft != null) homeLeft -= e.home ?? 0;
    // A refund kept without a split gave back under its one category.
    for (final (name, value)
        in e.parts.isEmpty ? [(e.category, e.amount)] : e.parts) {
      if (partsLeft.containsKey(name)) {
        partsLeft[name] = partsLeft[name]! - value;
      }
    }
  }
  final home = homeLeft == null
      ? null
      : amountLeft <= 0 || amount >= amountLeft
      ? homeLeft
      : _share(homeLeft, amount, amountLeft);
  final open = [
    for (final MapEntry(:key, :value) in partsLeft.entries)
      if (value > 0) (key, value),
  ];
  final parts = open.isEmpty || amount <= 0
      ? const <(String, int)>[]
      : _allocate(amount, open);
  return (
    home: home,
    parts: parts.length < 2 ? const [] : parts,
    category: parts.isEmpty ? original.category : parts.first.$1,
    tags: original.tags,
  );
}

/// [whole] × [part] / [of], rounded half away from zero.
int _share(int whole, int part, int of) => Money.quantizeRatio(
  Currency.units,
  BigInt.from(whole) * BigInt.from(part),
  BigInt.from(of),
).minorUnits.toInt();

/// [amount] shared over [weights] by the largest remainder, parts of
/// nothing left out.
List<(String, int)> _allocate(int amount, List<(String, int)> weights) {
  final shares = Money(
    Currency.units,
    BigInt.from(amount),
  ).allocate([for (final (_, w) in weights) BigInt.from(w)]);
  return [
    for (final (i, (name, _)) in weights.indexed)
      if (shares[i].minorUnits != BigInt.zero)
        (name, shares[i].minorUnits.toInt()),
  ];
}
