/// Sums of prices and rates worked out exactly. A close or a rate comes as
/// a decimal (662.05, 32.1125), which a double holds only nearly: a sum
/// that lands on a half, such as 2,730 shares at 662.05, could round the
/// wrong way. Each price is taken to 1/10,000 and each rate to
/// 1/1,000,000, which every close and rate published has room for, and
/// the sum is then whole numbers only, rounded half away from zero as
/// [double.round] does.
library;

/// Steps of a price: 1/10,000 of the currency's unit.
const priceScale = 10000;

/// Steps of a rate: 1/1,000,000.
const rateScale = 1000000;

/// [price] in steps of [priceScale].
int scaledPrice(double price) => (price * priceScale).round();

/// [rate] in steps of [rateScale].
BigInt scaledRate(double rate) => BigInt.from((rate * rateScale).round());

/// [numerator] / [denominator], rounded half away from zero; [denominator]
/// is positive.
int roundedQuotient(int numerator, int denominator) {
  final whole = numerator.abs() ~/ denominator;
  final rest = numerator.abs() % denominator;
  final rounded = 2 * rest >= denominator ? whole + 1 : whole;
  return numerator < 0 ? -rounded : rounded;
}

/// [roundedQuotient] for numbers too large for an int.
int roundedBigQuotient(BigInt numerator, BigInt denominator) {
  final size = numerator.abs();
  final whole = size ~/ denominator;
  final rest = size % denominator;
  final rounded = rest * BigInt.two >= denominator ? whole + BigInt.one : whole;
  return (numerator.isNegative ? -rounded : rounded).toInt();
}

/// [count] of something at [price] each, in whole units.
int timesPrice(int count, double price) =>
    roundedQuotient(count * scaledPrice(price), priceScale);
