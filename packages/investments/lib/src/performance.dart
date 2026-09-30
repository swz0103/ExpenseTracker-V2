import 'package:foundation_values/foundation_values.dart';

import 'buy.dart';
import 'sell.dart';

enum InvestmentPerformanceError {
  invalidInput,
  duplicateLot,
  identityMismatch,
  currencyMismatch,
}

final class InvestmentPerformanceException implements Exception {
  const InvestmentPerformanceException(this.code);
  final InvestmentPerformanceError code;

  @override
  String toString() => 'InvestmentPerformanceException(${code.name})';
}

/// A single instrument and investment account, in its trading currency.
/// Realized results and dividends must come from committed facts. A missing or
/// unusable quote leaves unrealized and total return unavailable for open lots.
final class InvestmentPerformance {
  InvestmentPerformance._({
    required this.quantityUnits,
    required this.remainingCost,
    required this.realizedResult,
    required this.netDividends,
    required this.marketValue,
    required this.unrealizedResult,
    required this.totalReturn,
  });

  factory InvestmentPerformance.calculate({
    required PublicId investmentAccountId,
    required PublicId instrumentId,
    required Currency currency,
    required List<InvestmentHoldingLot> openLots,
    required List<Money> realizedResults,
    required List<Money> netDividends,
    ShareUnitPrice? usablePrice,
  }) {
    if (openLots.length > 10000 ||
        realizedResults.length > 100000 ||
        netDividends.length > 100000) {
      throw const InvestmentPerformanceException(
        InvestmentPerformanceError.invalidInput,
      );
    }
    final ids = <PublicId>{};
    var quantity = BigInt.zero;
    var remainingCost = BigInt.zero;
    for (final lot in openLots) {
      if (!ids.add(lot.id)) {
        throw const InvestmentPerformanceException(
          InvestmentPerformanceError.duplicateLot,
        );
      }
      if (lot.investmentAccountId != investmentAccountId ||
          lot.instrumentId != instrumentId) {
        throw const InvestmentPerformanceException(
          InvestmentPerformanceError.identityMismatch,
        );
      }
      if (lot.remainingCost.currency != currency) {
        throw const InvestmentPerformanceException(
          InvestmentPerformanceError.currencyMismatch,
        );
      }
      quantity +=
          lot.remainingQuantity.coefficient *
          BigInt.from(10).pow(12 - lot.remainingQuantity.scale);
      remainingCost += lot.remainingCost.minorUnits;
    }
    BigInt sumMoney(List<Money> values) {
      var sum = BigInt.zero;
      for (final value in values) {
        if (value.currency != currency) {
          throw const InvestmentPerformanceException(
            InvestmentPerformanceError.currencyMismatch,
          );
        }
        sum += value.minorUnits;
      }
      return sum;
    }

    if (usablePrice != null && usablePrice.currency != currency) {
      throw const InvestmentPerformanceException(
        InvestmentPerformanceError.currencyMismatch,
      );
    }
    final cost = Money(currency, remainingCost);
    final realized = Money(currency, sumMoney(realizedResults));
    final dividends = Money(currency, sumMoney(netDividends));
    // Closed positions have no market exposure and require no price. For open
    // positions the caller may pass only an available, usable observation.
    final value = quantity == BigInt.zero
        ? Money(currency, BigInt.zero)
        : usablePrice == null
        ? null
        : Money.quantizeRatio(
            currency,
            quantity * usablePrice.coefficient,
            BigInt.from(10).pow(12 + usablePrice.scale),
          );
    final unrealized = value == null ? null : value - cost;
    final total = unrealized == null
        ? null
        : Money(
            currency,
            unrealized.minorUnits + realized.minorUnits + dividends.minorUnits,
          );
    return InvestmentPerformance._(
      quantityUnits: quantity,
      remainingCost: cost,
      realizedResult: realized,
      netDividends: dividends,
      marketValue: value,
      unrealizedResult: unrealized,
      totalReturn: total,
    );
  }

  /// Exact quantity in units of 10^-12 share.
  final BigInt quantityUnits;
  final Money remainingCost;
  final Money realizedResult;
  final Money netDividends;
  final Money? marketValue;
  final Money? unrealizedResult;
  final Money? totalReturn;
}
