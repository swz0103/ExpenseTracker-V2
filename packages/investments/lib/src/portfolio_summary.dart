import 'package:foundation_values/foundation_values.dart';

import 'performance.dart';

enum InvestmentPortfolioError {
  invalidInput,
  duplicatePosition,
  currencyMismatch,
  inconsistentPerformance,
}

final class InvestmentPortfolioException implements Exception {
  const InvestmentPortfolioException(this.code);
  final InvestmentPortfolioError code;

  @override
  String toString() => 'InvestmentPortfolioException(${code.name})';
}

/// Identity and trading currency supplied by the caller's validated holding
/// projection. One account/instrument pair may appear only once in a summary.
final class InvestmentPositionPerformance {
  const InvestmentPositionPerformance({
    required this.investmentAccountId,
    required this.instrumentId,
    required this.tradingCurrency,
    required this.performance,
  });

  final PublicId investmentAccountId;
  final PublicId instrumentId;
  final Currency tradingCurrency;
  final InvestmentPerformance performance;
}

/// Totals within one currency only. Null valuation fields mean at least one
/// open position has no usable price; partial sums must not be shown as totals.
final class InvestmentCurrencySummary {
  const InvestmentCurrencySummary._({
    required this.currency,
    required this.positionCount,
    required this.openPositionCount,
    required this.missingPriceCount,
    required this.remainingCost,
    required this.realizedResult,
    required this.netDividends,
    required this.marketValue,
    required this.unrealizedResult,
    required this.totalReturn,
  });

  final Currency currency;
  final int positionCount;
  final int openPositionCount;
  final int missingPriceCount;
  bool get hasCompleteValuation => missingPriceCount == 0;
  final Money remainingCost;
  final Money realizedResult;
  final Money netDividends;
  final Money? marketValue;
  final Money? unrealizedResult;
  final Money? totalReturn;
}

final class _CurrencyBucket {
  int positions = 0;
  int openPositions = 0;
  int missingPrices = 0;
  BigInt cost = BigInt.zero;
  BigInt realized = BigInt.zero;
  BigInt dividends = BigInt.zero;
  BigInt value = BigInt.zero;
  BigInt unrealized = BigInt.zero;
  BigInt total = BigInt.zero;
}

/// No implicit FX conversion or cross-currency grand total. Every input must
/// already be an InvestmentPerformance calculated from committed facts and an
/// explicitly usable quote, when a quote exists.
final class InvestmentPortfolioSummary {
  InvestmentPortfolioSummary._(this.byCurrency);

  factory InvestmentPortfolioSummary.calculate(
    List<InvestmentPositionPerformance> positions,
  ) {
    if (positions.length > 10000) {
      throw const InvestmentPortfolioException(
        InvestmentPortfolioError.invalidInput,
      );
    }
    final identities = <(PublicId, PublicId)>{};
    final buckets = <Currency, _CurrencyBucket>{};
    for (final position in positions) {
      if (!identities.add((
        position.investmentAccountId,
        position.instrumentId,
      ))) {
        throw const InvestmentPortfolioException(
          InvestmentPortfolioError.duplicatePosition,
        );
      }
      final currency = position.tradingCurrency;
      final result = position.performance;
      if (result.remainingCost.currency != currency ||
          result.realizedResult.currency != currency ||
          result.netDividends.currency != currency ||
          (result.marketValue != null &&
              result.marketValue!.currency != currency) ||
          (result.unrealizedResult != null &&
              result.unrealizedResult!.currency != currency) ||
          (result.totalReturn != null &&
              result.totalReturn!.currency != currency)) {
        throw const InvestmentPortfolioException(
          InvestmentPortfolioError.currencyMismatch,
        );
      }
      final open = result.quantityUnits > BigInt.zero;
      final hasValue = result.marketValue != null;
      if (result.quantityUnits < BigInt.zero ||
          (hasValue != (result.unrealizedResult != null)) ||
          (hasValue != (result.totalReturn != null)) ||
          (!open && !hasValue) ||
          (hasValue &&
              (result.unrealizedResult!.minorUnits !=
                      result.marketValue!.minorUnits -
                          result.remainingCost.minorUnits ||
                  result.totalReturn!.minorUnits !=
                      result.unrealizedResult!.minorUnits +
                          result.realizedResult.minorUnits +
                          result.netDividends.minorUnits))) {
        throw const InvestmentPortfolioException(
          InvestmentPortfolioError.inconsistentPerformance,
        );
      }
      final bucket = buckets.putIfAbsent(currency, _CurrencyBucket.new);
      bucket.positions++;
      if (open) bucket.openPositions++;
      if (open && !hasValue) bucket.missingPrices++;
      bucket.cost += result.remainingCost.minorUnits;
      bucket.realized += result.realizedResult.minorUnits;
      bucket.dividends += result.netDividends.minorUnits;
      if (hasValue) {
        bucket.value += result.marketValue!.minorUnits;
        bucket.unrealized += result.unrealizedResult!.minorUnits;
        bucket.total += result.totalReturn!.minorUnits;
      }
    }
    final summaries = <Currency, InvestmentCurrencySummary>{};
    for (final entry in buckets.entries) {
      final currency = entry.key;
      final bucket = entry.value;
      final complete = bucket.missingPrices == 0;
      summaries[currency] = InvestmentCurrencySummary._(
        currency: currency,
        positionCount: bucket.positions,
        openPositionCount: bucket.openPositions,
        missingPriceCount: bucket.missingPrices,
        remainingCost: Money(currency, bucket.cost),
        realizedResult: Money(currency, bucket.realized),
        netDividends: Money(currency, bucket.dividends),
        marketValue: complete ? Money(currency, bucket.value) : null,
        unrealizedResult: complete ? Money(currency, bucket.unrealized) : null,
        totalReturn: complete ? Money(currency, bucket.total) : null,
      );
    }
    return InvestmentPortfolioSummary._(Map.unmodifiable(summaries));
  }

  final Map<Currency, InvestmentCurrencySummary> byCurrency;
}
