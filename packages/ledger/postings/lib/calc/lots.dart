import 'package:core/foundation_values.dart' show Currency;
import 'package:domain/investments.dart';
import 'package:kernel/kernel.dart';

import '../model/vocabulary.dart';

// A holding's lots read from its postings, and what a trade does to
// them by the app's own lot arithmetic (packages/domain): nothing about
// lots is worked out here but the way to and from postings.

/// One lot held: [sub] is the intent that made it, [units] 10^-12 of a
/// share as the lot arithmetic counts them.
typedef Lot = ({String sub, BigInt units, int cost});

/// What a trade does to one lot, in units and cost.
typedef LotChange = ({String sub, BigInt units, int cost});

/// The lots [postings] (a holding's, in book order) leave: each lot's
/// units and cost are the sums of the postings naming it, oldest lot
/// first; a lot with no shares left is not held.
List<Lot> lotsOf(List<Posting> postings) {
  final quantity = <String, int>{};
  final cost = <String, int>{};
  for (final p in postings) {
    quantity[p.sub] = (quantity[p.sub] ?? 0) + p.quantity;
    cost[p.sub] = (cost[p.sub] ?? 0) + p.amount;
  }
  return [
    for (final MapEntry(key: sub, value: q) in quantity.entries)
      if (q > 0) (sub: sub, units: countOf(q, unitsPerShare), cost: cost[sub]!),
  ];
}

/// The whole shares [lots] hold, rounded half up, as a holding's shares
/// are counted.
int sharesHeld(List<Lot> lots) {
  final units = lots.fold(BigInt.zero, (sum, l) => sum + l.units);
  return ((units * BigInt.two + unitsPerShare) ~/ (unitsPerShare * BigInt.two))
      .toInt();
}

List<LotPosition> _positions(List<Lot> lots) => [
  for (final l in lots) LotPosition(l.units, BigInt.from(l.cost)),
];

List<LotChange> _changes(List<Lot> before, List<LotPosition> after) => [
  for (final (i, lot) in before.indexed)
    if (after[i].units != lot.units || after[i].cost.toInt() != lot.cost)
      (
        sub: lot.sub,
        units: after[i].units - lot.units,
        cost: after[i].cost.toInt() - lot.cost,
      ),
];

/// What selling [shares] takes from [lots], and what they cost: oldest
/// lots first, or at the average cost ([sellFromLots]). Null when more
/// is sold than is held.
({List<LotChange> changes, int cost})? sale(
  List<Lot> lots,
  int shares, {
  required bool average,
}) {
  final held = lots.fold(BigInt.zero, (sum, l) => sum + l.units);
  final selling = BigInt.from(shares) * unitsPerShare;
  if (selling > held) return null;
  final sold = sellFromLots(
    _positions(lots),
    selling,
    average ? InvestmentCostMethod.averageCost : InvestmentCostMethod.fifo,
  );
  return (changes: _changes(lots, sold.remaining), cost: sold.cost.toInt());
}

/// What [newShares] for every [oldShares] does to [lots] ([reratioLots]),
/// with its fallback: lots that cannot be re-ratioed exactly are pooled
/// into the newest first. [dropped] is the cost of a fraction of a share
/// dropped, [lowered] the capital returned off the cost.
({List<LotChange> changes, int dropped, int lowered}) reratio(
  List<Lot> lots, {
  required int newShares,
  required int oldShares,
  required CurrencyCode currency,
  bool wholeShares = true,
  int capitalReturned = 0,
}) {
  LotReratio? change(List<Lot> from) => reratioLots(
    _positions(from),
    newShares: newShares,
    oldShares: oldShares,
    currency: Currency.of(currency.value),
    wholeSharesOnly: wholeShares,
    capitalReturned: BigInt.from(capitalReturned),
  );
  final direct = change(lots);
  if (direct != null) {
    return (
      changes: _changes(lots, direct.lots),
      dropped: direct.droppedCost.toInt(),
      lowered: direct.basisLowered.toInt(),
    );
  }
  final last = lots.last;
  final pooled = (
    sub: last.sub,
    units: lots.fold(BigInt.zero, (sum, l) => sum + l.units),
    cost: lots.fold(0, (sum, l) => sum + l.cost),
  );
  final result = change([pooled])!;
  final after = result.lots.single;
  return (
    changes: [
      for (final lot in lots.take(lots.length - 1))
        (sub: lot.sub, units: -lot.units, cost: -lot.cost),
      (
        sub: last.sub,
        units: after.units - last.units,
        cost: after.cost.toInt() - last.cost,
      ),
    ],
    dropped: result.droppedCost.toInt(),
    lowered: result.basisLowered.toInt(),
  );
}

/// [changes] as lines on [holding]. A lot finer than a millionth of a
/// share is rounded half to even (`roundedQuantity`, decision D48) and
/// counted in [Lines.rounded], never silently; one of more than
/// [maxQuantity] is refused.
Posted lotLines(
  AccountId holding,
  List<LotChange> changes,
  CurrencyCode currency,
) {
  final lines = <Line>[];
  var rounded = 0;
  for (final change in changes) {
    final int quantity;
    switch (quantityOf(change.units, unitsPerShare)) {
      case ExactQuantity(:final value):
        quantity = value;
      case TooFine():
        rounded++;
        quantity = roundedQuantity(change.units, unitsPerShare);
      case TooLarge():
        return const Refused(Refusals.quantityTooLarge);
    }
    lines.add(
      Line(holding, change.cost, currency, quantity: quantity, sub: change.sub),
    );
  }
  return Lines(lines, rounded: rounded);
}

/// [shares] whole shares as a quantity.
int quantityOfShares(int shares) => shares * quantityScale;
