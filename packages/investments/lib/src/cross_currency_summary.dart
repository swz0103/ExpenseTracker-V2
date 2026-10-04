import 'package:foundation_values/foundation_values.dart';

import 'portfolio_summary.dart';

enum CrossCurrencyPortfolioError { duplicateRate, invalidRate }

final class CrossCurrencyPortfolioException implements Exception {
  const CrossCurrencyPortfolioException(this.code);
  final CrossCurrencyPortfolioError code;
}

enum PortfolioFxState { identity, exact, earlier, missing }

final class PortfolioFxInput {
  const PortfolioFxInput({
    required this.observation,
    required this.derivedInverse,
  });

  final FxObservation observation;
  final bool derivedInverse;
}

/// Cost, realized result and dividends of one currency's holdings already
/// in the reporting currency at the rates of their own dates (health check
/// G2-01), for example from TWD-settled trades or booked home values.
final class BookedInvestmentValues {
  const BookedInvestmentValues({
    required this.remainingCost,
    required this.realizedResult,
    required this.netDividends,
  });

  final Money remainingCost;
  final Money realizedResult;
  final Money netDividends;
}

final class ConvertedInvestmentCurrencySummary {
  const ConvertedInvestmentCurrencySummary({
    required this.original,
    required this.state,
    required this.observation,
    required this.derivedInverse,
    required this.remainingCost,
    required this.realizedResult,
    required this.netDividends,
    required this.marketValue,
    required this.unrealizedResult,
    required this.totalReturn,
    this.bookedCost = false,
  });

  final InvestmentCurrencySummary original;

  /// True when cost, realized result and dividends are at their historical
  /// rates; otherwise they are converted at the valuation date's rate.
  final bool bookedCost;
  final PortfolioFxState state;
  final FxObservation? observation;
  final bool derivedInverse;
  final Money? remainingCost;
  final Money? realizedResult;
  final Money? netDividends;
  final Money? marketValue;
  final Money? unrealizedResult;
  final Money? totalReturn;
  bool get hasUsableFx => state != PortfolioFxState.missing;
}

/// Read-only reporting conversion. Original per-currency totals stay
/// authoritative. Every non-identity conversion retains its actual provider
/// observation; no request date, 1:1 fallback or silent cross-rate is invented.
final class CrossCurrencyInvestmentSummary {
  CrossCurrencyInvestmentSummary._({
    required this.original,
    required this.reportingCurrency,
    required this.valuationDate,
    required this.rows,
    required this.remainingCost,
    required this.realizedResult,
    required this.netDividends,
    required this.marketValue,
    required this.unrealizedResult,
    required this.totalReturn,
  });

  factory CrossCurrencyInvestmentSummary.convert({
    required InvestmentPortfolioSummary original,
    required Currency reportingCurrency,
    required BusinessDate valuationDate,
    required Iterable<PortfolioFxInput> observations,
    bool allowEarlier = false,
    Map<Currency, BookedInvestmentValues> booked = const {},
  }) {
    for (final values in booked.values) {
      if (values.remainingCost.currency != reportingCurrency ||
          values.realizedResult.currency != reportingCurrency ||
          values.netDividends.currency != reportingCurrency) {
        throw const CrossCurrencyPortfolioException(
          CrossCurrencyPortfolioError.invalidRate,
        );
      }
    }
    final candidates = <Currency, (PortfolioFxInput, bool)>{};
    for (final input in observations) {
      final observation = input.observation;
      final rate = observation.rate;
      Currency? source;
      var inverse = false;
      if (rate.quote == reportingCurrency && rate.base != reportingCurrency) {
        source = rate.base;
      } else if (rate.base == reportingCurrency &&
          rate.quote != reportingCurrency) {
        source = rate.quote;
        inverse = true;
      } else {
        continue;
      }
      if (candidates.containsKey(source)) {
        throw const CrossCurrencyPortfolioException(
          CrossCurrencyPortfolioError.duplicateRate,
        );
      }
      candidates[source] = (input, inverse);
    }

    final rows = <Currency, ConvertedInvestmentCurrencySummary>{};
    for (final entry in original.byCurrency.entries) {
      final currency = entry.key;
      final row = entry.value;
      if (currency == reportingCurrency) {
        rows[currency] = ConvertedInvestmentCurrencySummary(
          original: row,
          state: PortfolioFxState.identity,
          observation: null,
          derivedInverse: false,
          remainingCost: row.remainingCost,
          realizedResult: row.realizedResult,
          netDividends: row.netDividends,
          marketValue: row.marketValue,
          unrealizedResult: row.unrealizedResult,
          totalReturn: row.totalReturn,
        );
        continue;
      }
      final candidate = candidates[currency];
      FxRate? usable;
      PortfolioFxState state = PortfolioFxState.missing;
      if (candidate != null) {
        final observation = candidate.$1.observation;
        try {
          final published = observation.rateFor(
            valuationDate,
            allowEarlier: allowEarlier,
          );
          usable = candidate.$2 ? published.inverse() : published;
          if (usable.base != currency || usable.quote != reportingCurrency) {
            throw const CrossCurrencyPortfolioException(
              CrossCurrencyPortfolioError.invalidRate,
            );
          }
          state = observation.asOf == valuationDate
              ? PortfolioFxState.exact
              : PortfolioFxState.earlier;
        } on FxException {
          usable = null;
        }
      }
      Money? convert(Money? amount) =>
          amount == null ? null : usable?.convert(amount);
      final history = booked[currency];
      final marketValue = convert(row.marketValue);
      final cost = history?.remainingCost ?? convert(row.remainingCost);
      final realized = history?.realizedResult ?? convert(row.realizedResult);
      final dividends = history?.netDividends ?? convert(row.netDividends);
      // Historical amounts keep their own rates; only the market value is
      // at the valuation date's rate (health check G2-01).
      Money? unrealized;
      Money? total;
      if (history == null) {
        unrealized = convert(row.unrealizedResult);
        total = convert(row.totalReturn);
      } else if (marketValue != null) {
        unrealized = marketValue - history.remainingCost;
        total = unrealized + history.realizedResult + history.netDividends;
      }
      rows[currency] = ConvertedInvestmentCurrencySummary(
        original: row,
        state: state,
        observation: candidate?.$1.observation,
        derivedInverse:
            (candidate?.$1.derivedInverse ?? false) || (candidate?.$2 ?? false),
        remainingCost: cost,
        realizedResult: realized,
        netDividends: dividends,
        marketValue: marketValue,
        unrealizedResult: unrealized,
        totalReturn: total,
        bookedCost: history != null,
      );
    }

    Money? sum(Money? Function(ConvertedInvestmentCurrencySummary) select) {
      if (rows.isEmpty) return null;
      var total = BigInt.zero;
      for (final row in rows.values) {
        final value = select(row);
        if (value == null || value.currency != reportingCurrency) return null;
        total += value.minorUnits;
      }
      return Money(reportingCurrency, total);
    }

    return CrossCurrencyInvestmentSummary._(
      original: original,
      reportingCurrency: reportingCurrency,
      valuationDate: valuationDate,
      rows: Map.unmodifiable(rows),
      remainingCost: sum((row) => row.remainingCost),
      realizedResult: sum((row) => row.realizedResult),
      netDividends: sum((row) => row.netDividends),
      marketValue: sum((row) => row.marketValue),
      unrealizedResult: sum((row) => row.unrealizedResult),
      totalReturn: sum((row) => row.totalReturn),
    );
  }

  final InvestmentPortfolioSummary original;
  final Currency reportingCurrency;
  final BusinessDate valuationDate;
  final Map<Currency, ConvertedInvestmentCurrencySummary> rows;
  final Money? remainingCost;
  final Money? realizedResult;
  final Money? netDividends;
  final Money? marketValue;
  final Money? unrealizedResult;
  final Money? totalReturn;

  bool get hasCompleteFx => rows.values.every((row) => row.hasUsableFx);
  bool get hasCompleteValuation => marketValue != null;
}
