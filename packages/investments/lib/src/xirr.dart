import 'dart:math' as math;

import 'package:foundation_values/foundation_values.dart';

/// Signed external investment cash flow in the instrument's currency.
/// Purchases are negative; sales, cash dividends and a separately dated final
/// valuation are positive. Reinvested amounts must be represented explicitly.
final class InvestmentCashFlow {
  const InvestmentCashFlow(this.date, this.amount);
  final BusinessDate date;
  final Money amount;
}

enum InvestmentXirrStatus {
  available,
  noSolution,
  multipleRoots,
  outsideSearchRange,
  nonConvergent,
}

final class InvestmentXirrResult {
  const InvestmentXirrResult(this.status, [this.annualRate]);
  final InvestmentXirrStatus status;

  /// Approximate annual rate, e.g. 0.1 means 10%. Money stays exact; only the
  /// rate solver uses floating-point and no persisted financial fact uses it.
  final double? annualRate;
}

/// Calendar-day XIRR using ACT/365.25 and a bounded search on ln(1 + rate).
/// A single sign-changing root is required; ambiguous or missing roots are
/// reported instead of selecting an arbitrary answer.
InvestmentXirrResult calculateInvestmentXirr({
  required Currency currency,
  required List<InvestmentCashFlow> flows,
}) {
  if (flows.length < 2 || flows.length > 10000) {
    return const InvestmentXirrResult(InvestmentXirrStatus.noSolution);
  }
  final byDate = <BusinessDate, BigInt>{};
  for (final flow in flows) {
    if (flow.amount.currency != currency) {
      throw const MoneyException(MoneyError.currencyMismatch);
    }
    byDate.update(
      flow.date,
      (sum) => sum + flow.amount.minorUnits,
      ifAbsent: () => flow.amount.minorUnits,
    );
  }
  final dates = byDate.keys.toList()..sort();
  if (dates.length < 2 ||
      !byDate.values.any((amount) => amount.isNegative) ||
      !byDate.values.any((amount) => amount > BigInt.zero)) {
    return const InvestmentXirrResult(InvestmentXirrStatus.noSolution);
  }
  final first = DateTime.utc(
    dates.first.year,
    dates.first.month,
    dates.first.day,
  );
  final terms = [
    for (final date in dates)
      (
        byDate[date]!.toDouble(),
        DateTime.utc(date.year, date.month, date.day).difference(first).inDays /
            365.25,
      ),
  ];

  // Divide all discounted terms by the largest exponential factor. This does
  // not change the root's sign and avoids overflow for long-lived portfolios.
  (double, double) evaluate(double logFactor) {
    var maximum = double.negativeInfinity;
    for (final term in terms) {
      maximum = math.max(maximum, -logFactor * term.$2);
    }
    var value = 0.0;
    var absolute = 0.0;
    for (final term in terms) {
      final weighted = term.$1 * math.exp(-logFactor * term.$2 - maximum);
      value += weighted;
      absolute += weighted.abs();
    }
    return (value, absolute);
  }

  int sign((double, double) result) {
    if (!result.$1.isFinite || !result.$2.isFinite) return 2;
    if (result.$2 == 0 || result.$1.abs() <= result.$2 * 1e-12) return 0;
    return result.$1.isNegative ? -1 : 1;
  }

  const minimum = -14.0; // annual return just above -100%
  final maximum = math.log(1001.0); // up to +100000% annualized
  const samples = 512;
  final exact = <double>[];
  final brackets = <(double, double)>[];
  var previousX = minimum;
  var previousSign = sign(evaluate(previousX));
  if (previousSign == 0) exact.add(previousX);
  for (var index = 1; index <= samples; index++) {
    final x = minimum + (maximum - minimum) * index / samples;
    final currentSign = sign(evaluate(x));
    if (currentSign == 2) {
      return const InvestmentXirrResult(InvestmentXirrStatus.nonConvergent);
    }
    if (currentSign == 0) {
      exact.add(x);
    } else if (previousSign != 0 && previousSign != currentSign) {
      brackets.add((previousX, x));
    }
    previousX = x;
    previousSign = currentSign;
  }
  // Consecutive near-zero samples can describe one flat crossing. Collapse
  // those, but never hide a second separated root.
  final distinctExact = <double>[];
  for (final x in exact) {
    if (distinctExact.isEmpty ||
        x - distinctExact.last > 2 * (maximum - minimum) / samples) {
      distinctExact.add(x);
    }
  }
  if (distinctExact.length + brackets.length > 1) {
    return const InvestmentXirrResult(InvestmentXirrStatus.multipleRoots);
  }
  if (distinctExact.isNotEmpty) {
    return InvestmentXirrResult(
      InvestmentXirrStatus.available,
      math.exp(distinctExact.single) - 1,
    );
  }
  if (brackets.isEmpty) {
    var lastFlowSign = 0;
    var changes = 0;
    for (final date in dates) {
      final value = byDate[date]!;
      final flowSign = value.isNegative
          ? -1
          : value > BigInt.zero
          ? 1
          : 0;
      if (flowSign == 0) continue;
      if (lastFlowSign != 0 && flowSign != lastFlowSign) changes++;
      lastFlowSign = flowSign;
    }
    if (changes == 1) {
      return const InvestmentXirrResult(
        InvestmentXirrStatus.outsideSearchRange,
      );
    }
    return const InvestmentXirrResult(InvestmentXirrStatus.noSolution);
  }
  var low = brackets.single.$1;
  var high = brackets.single.$2;
  var lowSign = sign(evaluate(low));
  for (var iteration = 0; iteration < 160; iteration++) {
    final middle = (low + high) / 2;
    final middleSign = sign(evaluate(middle));
    if (middleSign == 0 || high - low < 1e-12) {
      final rate = math.exp(middle) - 1;
      return rate.isFinite
          ? InvestmentXirrResult(InvestmentXirrStatus.available, rate)
          : const InvestmentXirrResult(InvestmentXirrStatus.nonConvergent);
    }
    if (middleSign == 2) {
      return const InvestmentXirrResult(InvestmentXirrStatus.nonConvergent);
    }
    if (middleSign == lowSign) {
      low = middle;
      lowSign = middleSign;
    } else {
      high = middle;
    }
  }
  return const InvestmentXirrResult(InvestmentXirrStatus.nonConvergent);
}
