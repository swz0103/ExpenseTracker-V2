import 'package:foundation_values/foundation_values.dart';

import 'buy.dart';
import 'sell.dart';
import 'stock_split.dart';

/// One lot after a corporate action. A quantity of zero closes the lot.
final class CorporateActionLotChange {
  const CorporateActionLotChange({
    required this.before,
    required this.afterUnits,
    required this.afterCost,
  });

  final InvestmentHoldingLot before;

  /// Shares in units of 10^-12.
  final BigInt afterUnits;
  final Money afterCost;
}

/// A change to a holding decided by the company (health check G2-16):
/// a stock dividend (1,050 for 1,000), a capital reduction (600 for 1,000)
/// or a reverse split, with the cash it pays.
///
/// Shares change by [newShares] for [oldShares]. On a whole-share market
/// the fraction left over is dropped from the newest lots and paid as
/// [cashInLieu]; its cost comes off the basis and the difference is a
/// realized result. [capitalReturned], from a cash capital reduction, comes
/// off the remaining basis in proportion to each lot's cost; anything above
/// the basis is a realized gain.
final class CorporateActionPreview {
  CorporateActionPreview._({
    required this.id,
    required this.lots,
    required this.cash,
    required this.realized,
  });

  factory CorporateActionPreview.create({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate effectiveOn,
    required InvestmentAccount account,
    required InvestmentInstrument instrument,
    required int newShares,
    required int oldShares,
    required List<InvestmentHoldingLot> lots,
    Money? cashInLieu,
    Money? capitalReturned,
  }) {
    final currency = instrument.tradingCurrency;
    if (newShares < 1 ||
        oldShares < 1 ||
        newShares > 1000000000 ||
        oldShares > 1000000000) {
      throw const StockSplitException(StockSplitError.invalidRatio);
    }
    if (operation.workspace != account.workspace) {
      throw const StockSplitException(StockSplitError.workspaceMismatch);
    }
    if (lots.isEmpty) {
      throw const StockSplitException(StockSplitError.emptyLots);
    }
    for (final money in [cashInLieu, capitalReturned]) {
      if (money != null &&
          (money.currency != currency || money.minorUnits <= BigInt.zero)) {
        throw const InvestmentException(InvestmentError.invalidInput);
      }
    }
    final ordered = List<InvestmentHoldingLot>.of(lots)
      ..sort((a, b) {
        final byDate = a.acquiredOn.compareTo(b.acquiredOn);
        return byDate != 0 ? byDate : a.id.value.compareTo(b.id.value);
      });
    final seen = <PublicId>{};
    final units = <BigInt>[];
    for (final lot in ordered) {
      if (!seen.add(lot.id)) {
        throw const StockSplitException(StockSplitError.duplicateLot);
      }
      if (lot.investmentAccountId != account.id ||
          lot.instrumentId != instrument.id ||
          lot.remainingCost.currency != currency ||
          lot.id == id) {
        throw const StockSplitException(StockSplitError.identityMismatch);
      }
      if (lot.acquiredOn.compareTo(effectiveOn) > 0) {
        throw const StockSplitException(StockSplitError.invalidDate);
      }
      final before =
          lot.remainingQuantity.coefficient *
          BigInt.from(10).pow(12 - lot.remainingQuantity.scale);
      final expanded = before * BigInt.from(newShares);
      if (expanded.remainder(BigInt.from(oldShares)) != BigInt.zero) {
        throw const StockSplitException(StockSplitError.fractionalPrecision);
      }
      units.add(expanded ~/ BigInt.from(oldShares));
    }
    final costs = [for (final lot in ordered) lot.remainingCost.minorUnits];

    // Drop the fraction of a share, newest lots first.
    var realized = BigInt.zero;
    final share = BigInt.from(10).pow(12);
    final total = units.fold(BigInt.zero, (sum, unit) => sum + unit);
    var drop = instrument.wholeSharesOnly ? total % share : BigInt.zero;
    if (drop == BigInt.zero && cashInLieu != null) {
      throw const InvestmentException(InvestmentError.invalidInput);
    }
    for (var i = units.length - 1; i >= 0 && drop > BigInt.zero; i--) {
      if (units[i] == BigInt.zero) continue;
      final taken = drop < units[i] ? drop : units[i];
      final cost = _divideRounded(costs[i] * taken, units[i]);
      costs[i] -= cost;
      realized -= cost;
      units[i] -= taken;
      drop -= taken;
    }
    realized += cashInLieu?.minorUnits ?? BigInt.zero;

    // Returned capital lowers the basis; past it, it is a gain.
    final returned = capitalReturned?.minorUnits ?? BigInt.zero;
    final basis = costs.fold(BigInt.zero, (sum, cost) => sum + cost);
    final lowered = returned < basis ? returned : basis;
    realized += returned - lowered;
    if (lowered > BigInt.zero) {
      final weighted = [
        for (var i = 0; i < costs.length; i++)
          if (costs[i] > BigInt.zero) i,
      ];
      final lowering = Money(currency, lowered);
      final parts = lowering.allocate([for (final i in weighted) costs[i]]);
      for (final (n, i) in weighted.indexed) {
        costs[i] -= parts[n].minorUnits;
      }
    }

    final cash = (cashInLieu?.minorUnits ?? BigInt.zero) + returned;
    return CorporateActionPreview._(
      id: id,
      lots: List.unmodifiable([
        for (var i = 0; i < ordered.length; i++)
          CorporateActionLotChange(
            before: ordered[i],
            afterUnits: units[i],
            afterCost: Money(currency, costs[i]),
          ),
      ]),
      cash: Money(currency, cash),
      realized: Money(currency, realized),
    );
  }

  final PublicId id;
  final List<CorporateActionLotChange> lots;

  /// Cash paid out: cash in lieu plus returned capital.
  final Money cash;

  /// Cash in lieu less the cost of the dropped fraction, plus any capital
  /// returned beyond the basis.
  final Money realized;
}

BigInt _divideRounded(BigInt numerator, BigInt denominator) {
  final quotient = numerator ~/ denominator;
  if (numerator.remainder(denominator) * BigInt.two >= denominator) {
    return quotient + BigInt.one;
  }
  return quotient;
}
