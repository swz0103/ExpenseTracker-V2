import 'package:domain/investments.dart' show unitsPerShare;
import 'package:core/money/price.dart' show timesPrice;

final class Holding {
  const Holding(
    this.code,
    this.name, {
    required this.shares,
    required this.price,
    required this.cost,
    required this.change,
    this.dividends = 0,
    this.realized = 0,
  });

  final String code;
  final String name;
  final int shares;

  /// The reference close, in NT$ with decimals.
  final double price;

  /// What the shares still held cost.
  final int cost;

  /// Today's change in market value.
  final int change;

  /// Dividends received so far.
  final int dividends;

  /// Profit or loss of shares already sold.
  final int realized;

  int get value => timesPrice(shares, price);

  int get gain => value - cost;

  /// This holding with [change] as the day's change in value.
  Holding withChange(int change) => Holding(
    code,
    name,
    shares: shares,
    price: price,
    cost: cost,
    change: change,
    dividends: dividends,
    realized: realized,
  );

  Holding copyWith({
    int? shares,
    double? price,
    int? cost,
    int? dividends,
    int? realized,
  }) => Holding(
    code,
    name,
    shares: shares ?? this.shares,
    price: price ?? this.price,
    cost: cost ?? this.cost,
    change: change,
    dividends: dividends ?? this.dividends,
    realized: realized ?? this.realized,
  );
}

/// Shares bought together and still held, with what they cost.
final class Lot {
  /// A lot of whole [shares].
  Lot(this.date, int shares, this.cost)
    : units = BigInt.from(shares) * unitsPerShare;

  /// A lot of exact [units], 10^-12 of a share each, as a split or a
  /// stock dividend can leave it.
  const Lot.units(this.date, this.units, this.cost);

  /// The date a starting position is held from: before any entry, so the
  /// first trade of a stock always comes after it.
  static final opening = DateTime.utc(1970);

  final DateTime date;
  final BigInt units;
  final int cost;

  /// Whole shares, rounded.
  int get shares => _divideRounded(units, unitsPerShare).toInt();

  /// Whether this lot is part of a starting position.
  bool get isOpening => date == opening;
}

BigInt _divideRounded(BigInt numerator, BigInt denominator) {
  final quotient = numerator ~/ denominator;
  return numerator.remainder(denominator) * BigInt.two >= denominator
      ? quotient + BigInt.one
      : quotient;
}
