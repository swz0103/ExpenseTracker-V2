import 'package:core/foundation_values.dart';

import 'sell.dart';

/// The arithmetic of holding lots, shared by the ledger and the screens so
/// both arrive at the same shares and cost: a sale by oldest lots or by
/// average cost, and a change of shares decided by the company.
///
/// Shares are exact units of 10^-12 of a share; costs are minor units.
/// Lots come oldest first.
final class LotPosition {
  const LotPosition(this.units, this.cost);

  final BigInt units;
  final BigInt cost;

  @override
  bool operator ==(Object other) =>
      other is LotPosition && other.units == units && other.cost == cost;

  @override
  int get hashCode => Object.hash(units, cost);

  @override
  String toString() => 'LotPosition($units, $cost)';
}

/// Units in one whole share.
final BigInt unitsPerShare = BigInt.from(10).pow(12);

/// What a sale takes from each lot and what each keeps.
final class LotSale {
  const LotSale({
    required this.sold,
    required this.saleCosts,
    required this.remaining,
  });

  /// Units taken from each lot.
  final List<BigInt> sold;

  /// The cost each lot gives up.
  final List<BigInt> saleCosts;

  /// Each lot after the sale; a lot sold out has no units.
  final List<LotPosition> remaining;

  /// The cost of the shares sold.
  BigInt get cost => saleCosts.fold(BigInt.zero, (sum, c) => sum + c);
}

/// Sells [quantity] units from [lots], oldest first.
///
/// By oldest lots ([InvestmentCostMethod.fifo]) a lot partly sold gives up
/// its cost in proportion, rounded down. By average cost the pooled cost
/// is rounded down once, and what stays is spread again over the lots
/// left, the last taking what rounding leaves. A final sale takes every
/// unit of cost. Throws an [ArgumentError] when [quantity] is negative or
/// more than the lots hold.
LotSale sellFromLots(
  List<LotPosition> lots,
  BigInt quantity,
  InvestmentCostMethod method,
) {
  final totalQuantity = lots.fold(BigInt.zero, (sum, l) => sum + l.units);
  final totalCost = lots.fold(BigInt.zero, (sum, l) => sum + l.cost);
  if (quantity < BigInt.zero || quantity > totalQuantity) {
    throw ArgumentError.value(quantity, 'quantity', 'more than held');
  }
  var toSell = quantity;
  final sold = <BigInt>[];
  final left = <BigInt>[];
  for (final lot in lots) {
    final taken = toSell < lot.units ? toSell : lot.units;
    sold.add(taken);
    left.add(lot.units - taken);
    toSell -= taken;
  }

  final saleCosts = List<BigInt>.filled(lots.length, BigInt.zero);
  final keptCosts = List<BigInt>.filled(lots.length, BigInt.zero);
  if (method == InvestmentCostMethod.fifo) {
    for (var i = 0; i < lots.length; i++) {
      final cost = lots[i].cost;
      final taken = sold[i] == lots[i].units
          ? cost
          : cost * sold[i] ~/ lots[i].units;
      saleCosts[i] = taken;
      keptCosts[i] = cost - taken;
    }
  } else if (quantity > BigInt.zero) {
    final allocated = quantity == totalQuantity
        ? totalCost
        : totalCost * quantity ~/ totalQuantity;
    _spread(allocated, sold, quantity, saleCosts);
    _spread(totalCost - allocated, left, totalQuantity - quantity, keptCosts);
  } else {
    for (var i = 0; i < lots.length; i++) {
      keptCosts[i] = lots[i].cost;
    }
  }
  return LotSale(
    sold: List.unmodifiable(sold),
    saleCosts: List.unmodifiable(saleCosts),
    remaining: List.unmodifiable([
      for (var i = 0; i < lots.length; i++) LotPosition(left[i], keptCosts[i]),
    ]),
  );
}

/// [amount] over the lots in proportion to [units], rounded down, the last
/// lot with units taking what rounding leaves.
void _spread(
  BigInt amount,
  List<BigInt> units,
  BigInt total,
  List<BigInt> into,
) {
  final last = units.lastIndexWhere((u) => u > BigInt.zero);
  var rest = amount;
  for (var i = 0; i <= last; i++) {
    if (units[i] == BigInt.zero) continue;
    final share = i == last ? rest : amount * units[i] ~/ total;
    into[i] = share;
    rest -= share;
  }
}

/// [units] after [newShares] for [oldShares], or null when the result is
/// not a whole number of units.
BigInt? reratioUnits(BigInt units, int newShares, int oldShares) {
  final expanded = units * BigInt.from(newShares);
  final divisor = BigInt.from(oldShares);
  if (expanded.remainder(divisor) != BigInt.zero) return null;
  return expanded ~/ divisor;
}

/// Lots after the company changes shares by [newShares] for [oldShares].
final class LotReratio {
  const LotReratio({
    required this.lots,
    required this.droppedUnits,
    required this.droppedCost,
    required this.basisLowered,
  });

  /// Each lot after the change, in the same order.
  final List<LotPosition> lots;

  /// The fraction of a share dropped, paid as cash in lieu.
  final BigInt droppedUnits;

  /// The cost of [droppedUnits].
  final BigInt droppedCost;

  /// How much returned capital came off the cost; anything above it is a
  /// realized gain.
  final BigInt basisLowered;
}

/// Every lot's shares re-ratioed by [newShares] for [oldShares], each lot
/// keeping its cost. With [wholeSharesOnly] the fraction of a share left
/// over is dropped from the newest lots, their cost going with it.
/// [capitalReturned] then comes off the cost in proportion to each lot's
/// cost, no further than the cost.
///
/// Returns null when a lot's units cannot be re-ratioed exactly.
LotReratio? reratioLots(
  List<LotPosition> lots, {
  required int newShares,
  required int oldShares,
  required Currency currency,
  bool wholeSharesOnly = false,
  BigInt? capitalReturned,
}) {
  final units = <BigInt>[];
  for (final lot in lots) {
    final after = reratioUnits(lot.units, newShares, oldShares);
    if (after == null) return null;
    units.add(after);
  }
  final costs = [for (final lot in lots) lot.cost];

  final total = units.fold(BigInt.zero, (sum, u) => sum + u);
  final dropped = wholeSharesOnly ? total % unitsPerShare : BigInt.zero;
  var drop = dropped;
  var droppedCost = BigInt.zero;
  for (var i = units.length - 1; i >= 0 && drop > BigInt.zero; i--) {
    if (units[i] == BigInt.zero) continue;
    final taken = drop < units[i] ? drop : units[i];
    final cost = _divideRounded(costs[i] * taken, units[i]);
    costs[i] -= cost;
    droppedCost += cost;
    units[i] -= taken;
    drop -= taken;
  }

  final returned = capitalReturned ?? BigInt.zero;
  final basis = costs.fold(BigInt.zero, (sum, c) => sum + c);
  final lowered = returned < basis ? returned : basis;
  if (lowered > BigInt.zero) {
    final weighted = [
      for (var i = 0; i < costs.length; i++)
        if (costs[i] > BigInt.zero) i,
    ];
    final parts = Money(
      currency,
      lowered,
    ).allocate([for (final i in weighted) costs[i]]);
    for (final (n, i) in weighted.indexed) {
      costs[i] -= parts[n].minorUnits;
    }
  }
  return LotReratio(
    lots: List.unmodifiable([
      for (var i = 0; i < units.length; i++) LotPosition(units[i], costs[i]),
    ]),
    droppedUnits: dropped,
    droppedCost: droppedCost,
    basisLowered: lowered,
  );
}

BigInt _divideRounded(BigInt numerator, BigInt denominator) {
  final quotient = numerator ~/ denominator;
  if (numerator.remainder(denominator) * BigInt.two >= denominator) {
    return quotient + BigInt.one;
  }
  return quotient;
}
