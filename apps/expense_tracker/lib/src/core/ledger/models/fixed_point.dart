/// Sums of rates worked out exactly. A rate comes as a decimal (32.1125),
/// which a double holds only nearly: a conversion that lands on a half
/// could round the wrong way. Each rate is taken to 1/1,000,000, which
/// every rate published has room for, and the sum is then whole numbers
/// only, rounded half away from zero. Sums of prices are core's
/// (`package:core/money/price.dart`).
library;

/// Steps of a rate: 1/1,000,000.
const rateScale = 1000000;

/// [rate] in steps of [rateScale].
BigInt scaledRate(double rate) => BigInt.from((rate * rateScale).round());

/// [numerator] / [denominator] rounded half away from zero, for numbers
/// too large for an int; [denominator] is positive.
int roundedBigQuotient(BigInt numerator, BigInt denominator) {
  final size = numerator.abs();
  final whole = size ~/ denominator;
  final rest = size % denominator;
  final rounded = rest * BigInt.two >= denominator ? whole + BigInt.one : whole;
  return (numerator.isNegative ? -rounded : rounded).toInt();
}
