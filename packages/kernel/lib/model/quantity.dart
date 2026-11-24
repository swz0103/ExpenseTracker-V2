/// How many parts of one unit (a share) a posting's quantity counts:
/// 10^12, the app's own lot arithmetic's (packages/domain `unitsPerShare`;
/// the postings package's tests hold the two the same). Exact, never
/// rounded (decision D87, in place of D48's millionth): a quantity is a
/// [BigInt], so no count of shares the app can hold overflows it.
final BigInt quantityScale = BigInt.from(10).pow(12);

/// The largest quantity kept: whole units as many as a 64-bit integer
/// holds, which is as many as the app's own counts of shares (an `int`)
/// can be. A file keeps a quantity as its whole units and its parts.
final BigInt maxQuantity = BigInt.from(_maxInt) * quantityScale;

const _maxInt = 9223372036854775807;

/// No quantity: a line of money.
final BigInt noQuantity = BigInt.zero;

/// [units] whole units (shares) as a quantity, exactly.
BigInt quantityOfUnits(int units) => BigInt.from(units) * quantityScale;

/// Whether [quantity] can be kept ([maxQuantity] either way).
bool keepable(BigInt quantity) => quantity.abs() <= maxQuantity;

/// A [quantity] in whole units, rounded half away from zero.
int wholeUnits(BigInt quantity) {
  final twice = quantity.abs() * BigInt.two + quantityScale;
  final whole = (twice ~/ (quantityScale * BigInt.two)).toInt();
  return quantity.isNegative ? -whole : whole;
}
