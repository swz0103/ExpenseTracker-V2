import 'package:foundation_values/foundation_values.dart';

import 'buy.dart';

enum InvestmentSellError {
  invalidInput,
  emptyLots,
  duplicateIdentity,
  workspaceMismatch,
  brokerMismatch,
  fundingAccountMismatch,
  identityMismatch,
  currencyMismatch,
  grossMismatch,
  oversell,
  nonPositiveNet,
  staleLots,
  overflow,

  /// Taiwan-listed shares trade in whole shares only (feature audit G-16).
  fractionalShares,
}

final class InvestmentSellException implements Exception {
  const InvestmentSellException(this.code);
  final InvestmentSellError code;

  @override
  String toString() => 'InvestmentSellException(${code.name})';
}

enum InvestmentCostMethod { fifo, averageCost }

/// An authoritative, unclosed holding snapshot. The caller must provide every
/// open lot for this account and instrument, then re-read them at commit time.
final class InvestmentHoldingLot {
  InvestmentHoldingLot({
    required this.id,
    required this.investmentAccountId,
    required this.instrumentId,
    required this.acquiredOn,
    required this.remainingQuantity,
    required this.remainingCost,
    required this.expectedVersion,
  }) {
    if (expectedVersion < 1 || remainingCost.minorUnits < BigInt.zero) {
      throw const InvestmentSellException(InvestmentSellError.invalidInput);
    }
  }

  final PublicId id;
  final PublicId investmentAccountId;
  final PublicId instrumentId;
  final BusinessDate acquiredOn;
  final ShareQuantity remainingQuantity;
  final Money remainingCost;
  final int expectedVersion;
}

/// Quantities use exact units of 10^-12 shares. Under Average Cost the
/// remaining basis can be rebalanced across lots, including untouched lots.
final class InvestmentLotSaleAllocation {
  const InvestmentLotSaleAllocation({
    required this.lot,
    required this.soldQuantityUnits,
    required this.allocatedSaleCost,
    required this.remainingQuantityUnits,
    required this.remainingCost,
  });

  final InvestmentHoldingLot lot;
  final BigInt soldQuantityUnits;
  final Money allocatedSaleCost;
  final BigInt remainingQuantityUnits;
  final Money remainingCost;
}

/// Pure sale proposal. Schema 22 must atomically check the operation receipt,
/// revalidate the full lot set, credit cash, and apply these lot changes. A
/// retry retains [id] and [operation]; a receipt wins before stale-lot checks.
final class InvestmentSellPreview {
  InvestmentSellPreview._({
    required this.id,
    required this.operation,
    required this.tradedOn,
    required this.broker,
    required this.account,
    required this.instrument,
    required this.funding,
    required this.costMethod,
    required this.quantity,
    required this.unitPrice,
    required this.gross,
    required this.fee,
    required this.tax,
    required this.netCashCredit,
    required this.allocatedCost,
    required this.realizedResult,
    required this.allocations,
    required this.exactGrossNumerator,
    required this.exactGrossDenominator,
  });

  factory InvestmentSellPreview.create({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate tradedOn,
    required BrokerIdentity broker,
    required InvestmentAccount account,
    required InvestmentInstrument instrument,
    required FundingCashAccount funding,
    required InvestmentCostMethod costMethod,
    required ShareQuantity quantity,
    required ShareUnitPrice unitPrice,
    required Money executedGross,
    required Money fee,
    required Money tax,
    required List<InvestmentHoldingLot> lots,
  }) {
    if (operation.workspace != broker.workspace ||
        operation.workspace != account.workspace ||
        operation.workspace != funding.workspace) {
      throw const InvestmentSellException(
        InvestmentSellError.workspaceMismatch,
      );
    }
    if (account.brokerId != broker.id) {
      throw const InvestmentSellException(InvestmentSellError.brokerMismatch);
    }
    if (account.fundingCashAccountId != funding.id) {
      throw const InvestmentSellException(
        InvestmentSellError.fundingAccountMismatch,
      );
    }
    final currency = instrument.tradingCurrency;
    if (funding.currency != currency ||
        unitPrice.currency != currency ||
        executedGross.currency != currency ||
        fee.currency != currency ||
        tax.currency != currency) {
      throw const InvestmentSellException(InvestmentSellError.currencyMismatch);
    }
    if (executedGross.minorUnits <= BigInt.zero ||
        fee.minorUnits < BigInt.zero ||
        tax.minorUnits < BigInt.zero) {
      throw const InvestmentSellException(InvestmentSellError.invalidInput);
    }
    final numerator = quantity.coefficient * unitPrice.coefficient;
    final denominator = BigInt.from(10).pow(quantity.scale + unitPrice.scale);
    final Money calculatedGross;
    try {
      calculatedGross = Money.quantizeRatio(currency, numerator, denominator);
    } on MoneyException catch (error) {
      if (error.code == MoneyError.overflow) {
        throw const InvestmentSellException(InvestmentSellError.overflow);
      }
      rethrow;
    }
    // One unit either side of the quote is broker rounding (G-16).
    if ((calculatedGross.minorUnits - executedGross.minorUnits).abs() >
        BigInt.one) {
      throw const InvestmentSellException(InvestmentSellError.grossMismatch);
    }
    if (instrument.wholeSharesOnly && !quantity.isWhole) {
      throw const InvestmentSellException(InvestmentSellError.fractionalShares);
    }
    final netUnits = executedGross.minorUnits - fee.minorUnits - tax.minorUnits;
    // Fees can eat the whole sale, as when selling nearly worthless
    // shares; the cash then moves the other way (health check G1-06).
    if (lots.isEmpty || lots.length > 10000) {
      throw const InvestmentSellException(InvestmentSellError.emptyLots);
    }
    // Same-day lots are ordered by lot id: ids are UUIDv7, so this is the
    // order they were bought in, and it does not depend on input order.
    final ordered = List<InvestmentHoldingLot>.of(lots)..sort(_compareLots);
    final ids = <PublicId>{};
    var totalQuantity = BigInt.zero;
    var totalCost = BigInt.zero;
    final quantities = <BigInt>[];
    for (final lot in ordered) {
      if (lot.id == id || !ids.add(lot.id)) {
        throw const InvestmentSellException(
          InvestmentSellError.duplicateIdentity,
        );
      }
      if (lot.investmentAccountId != account.id ||
          lot.instrumentId != instrument.id ||
          lot.acquiredOn.compareTo(tradedOn) > 0) {
        throw const InvestmentSellException(
          InvestmentSellError.identityMismatch,
        );
      }
      if (lot.remainingCost.currency != currency) {
        throw const InvestmentSellException(
          InvestmentSellError.currencyMismatch,
        );
      }
      final units = _quantityUnits(lot.remainingQuantity);
      quantities.add(units);
      totalQuantity += units;
      totalCost += lot.remainingCost.minorUnits;
    }
    final saleQuantity = _quantityUnits(quantity);
    if (saleQuantity > totalQuantity) {
      throw const InvestmentSellException(InvestmentSellError.oversell);
    }
    if (totalCost > Money.maxMinorUnits ||
        netUnits - totalCost < Money.minMinorUnits) {
      throw const InvestmentSellException(InvestmentSellError.overflow);
    }

    var toSell = saleQuantity;
    final sold = <BigInt>[];
    final remaining = <BigInt>[];
    for (final lotQuantity in quantities) {
      final disposed = toSell < lotQuantity ? toSell : lotQuantity;
      sold.add(disposed);
      remaining.add(lotQuantity - disposed);
      toSell -= disposed;
    }
    assert(toSell == BigInt.zero);

    final saleCosts = List<BigInt>.filled(ordered.length, BigInt.zero);
    final remainingCosts = List<BigInt>.filled(ordered.length, BigInt.zero);
    final BigInt allocatedUnits;
    if (costMethod == InvestmentCostMethod.fifo) {
      var cost = BigInt.zero;
      for (var index = 0; index < ordered.length; index++) {
        final lotCost = ordered[index].remainingCost.minorUnits;
        final consumed = sold[index] == quantities[index]
            ? lotCost
            : lotCost * sold[index] ~/ quantities[index];
        saleCosts[index] = consumed;
        remainingCosts[index] = lotCost - consumed;
        cost += consumed;
      }
      allocatedUnits = cost;
    } else {
      // Pooled average cost is rounded only once. On a final sale every
      // residual minor unit is consumed; partial sales truncate toward zero.
      allocatedUnits = saleQuantity == totalQuantity
          ? totalCost
          : totalCost * saleQuantity ~/ totalQuantity;
      var costRemainder = allocatedUnits;
      final lastSold = sold.lastIndexWhere((units) => units > BigInt.zero);
      for (var index = 0; index <= lastSold; index++) {
        if (sold[index] == BigInt.zero) continue;
        final share = index == lastSold
            ? costRemainder
            : allocatedUnits * sold[index] ~/ saleQuantity;
        saleCosts[index] = share;
        costRemainder -= share;
      }
      final remainingTotal = totalCost - allocatedUnits;
      final remainingQuantity = totalQuantity - saleQuantity;
      var remainingRemainder = remainingTotal;
      final lastOpen = remaining.lastIndexWhere((units) => units > BigInt.zero);
      for (var index = 0; index <= lastOpen; index++) {
        if (remaining[index] == BigInt.zero) continue;
        final share = index == lastOpen
            ? remainingRemainder
            : remainingTotal * remaining[index] ~/ remainingQuantity;
        remainingCosts[index] = share;
        remainingRemainder -= share;
      }
    }
    final allocations = <InvestmentLotSaleAllocation>[];
    for (var index = 0; index < ordered.length; index++) {
      allocations.add(
        InvestmentLotSaleAllocation(
          lot: ordered[index],
          soldQuantityUnits: sold[index],
          allocatedSaleCost: Money(currency, saleCosts[index]),
          remainingQuantityUnits: remaining[index],
          remainingCost: Money(currency, remainingCosts[index]),
        ),
      );
    }
    return InvestmentSellPreview._(
      id: id,
      operation: operation,
      tradedOn: tradedOn,
      broker: broker,
      account: account,
      instrument: instrument,
      funding: funding,
      costMethod: costMethod,
      quantity: quantity,
      unitPrice: unitPrice,
      gross: executedGross,
      fee: fee,
      tax: tax,
      netCashCredit: Money(currency, netUnits),
      allocatedCost: Money(currency, allocatedUnits),
      realizedResult: Money(currency, netUnits - allocatedUnits),
      allocations: List.unmodifiable(allocations),
      exactGrossNumerator: numerator,
      exactGrossDenominator: denominator,
    );
  }

  final PublicId id;
  PublicId get sellId => id;
  final OperationKey operation;
  final BusinessDate tradedOn;
  final BrokerIdentity broker;
  final InvestmentAccount account;
  final InvestmentInstrument instrument;
  final FundingCashAccount funding;
  final InvestmentCostMethod costMethod;
  final ShareQuantity quantity;
  final ShareUnitPrice unitPrice;
  final Money gross;
  final Money fee;
  final Money tax;
  final Money netCashCredit;
  Money get cashCredit => netCashCredit;
  final Money allocatedCost;
  final Money realizedResult;
  final List<InvestmentLotSaleAllocation> allocations;
  final BigInt exactGrossNumerator;
  final BigInt exactGrossDenominator;
  static const quantityScale = 12;
  static const settlementRoundingPolicy = 'half-away-from-zero-v1';
  static const basisAllocationPolicy = 'truncate-last-remainder-v1';

  /// Call inside the posting transaction with every current open lot. Missing,
  /// additional, version-changed, or value-changed lots invalidate the quote.
  void verifyCurrentLots(List<InvestmentHoldingLot> currentLots) {
    if (currentLots.length != allocations.length) {
      throw const InvestmentSellException(InvestmentSellError.staleLots);
    }
    final current = List<InvestmentHoldingLot>.of(currentLots)
      ..sort(_compareLots);
    for (var index = 0; index < current.length; index++) {
      final expected = allocations[index].lot;
      final actual = current[index];
      if (actual.id != expected.id ||
          actual.investmentAccountId != expected.investmentAccountId ||
          actual.instrumentId != expected.instrumentId ||
          actual.acquiredOn != expected.acquiredOn ||
          actual.remainingQuantity != expected.remainingQuantity ||
          actual.remainingCost != expected.remainingCost ||
          actual.expectedVersion != expected.expectedVersion) {
        throw const InvestmentSellException(InvestmentSellError.staleLots);
      }
    }
  }
}

BigInt _quantityUnits(ShareQuantity quantity) =>
    quantity.coefficient * BigInt.from(10).pow(12 - quantity.scale);

int _compareLots(InvestmentHoldingLot a, InvestmentHoldingLot b) {
  final dateComparison = a.acquiredOn.compareTo(b.acquiredOn);
  return dateComparison == 0
      ? a.id.value.compareTo(b.id.value)
      : dateComparison;
}
