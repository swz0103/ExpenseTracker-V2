/// How many parts of one unit (a share) a posting's quantity counts: a
/// millionth. A finer scale (the lot arithmetic counts 10^-12) would
/// leave a 64-bit column room for only about nine million shares; this
/// one leaves room for nine billion, and every quantity is checked on
/// the way in ([quantityOf]).
const quantityScale = 1000000;

/// The largest quantity kept: the largest whole number every platform
/// the app runs on holds exactly (2^53 - 1), about nine billion units.
const maxQuantity = 9007199254740991;

/// What became of a count on its way to a posting's quantity.
sealed class QuantityConversion {
  const QuantityConversion();
}

/// The count as a quantity, exactly.
final class ExactQuantity extends QuantityConversion {
  const ExactQuantity(this.value);
  final int value;
}

/// The count has a part smaller than a millionth of a unit, which a
/// quantity cannot hold; nothing is rounded silently.
final class TooFine extends QuantityConversion {
  const TooFine();
}

/// The count is more than [maxQuantity] can hold.
final class TooLarge extends QuantityConversion {
  const TooLarge();
}

/// [count] parts, [perUnit] of them to one unit, as a posting's quantity:
/// checked, never rounded. [perUnit] is a multiple of [quantityScale]
/// (the lot arithmetic's 10^12 is).
QuantityConversion quantityOf(BigInt count, BigInt perUnit) {
  final step = perUnit ~/ _scale;
  if (step * _scale != perUnit) {
    throw ArgumentError.value(perUnit, 'perUnit', 'not a multiple of scale');
  }
  if (count.remainder(step) != BigInt.zero) return const TooFine();
  final quantity = count ~/ step;
  if (quantity.abs() > _max) return const TooLarge();
  return ExactQuantity(quantity.toInt());
}

/// A posting's [quantity] back as parts, [perUnit] of them to one unit.
BigInt countOf(int quantity, BigInt perUnit) =>
    BigInt.from(quantity) * (perUnit ~/ _scale);

/// A [quantity] in whole units, rounded half away from zero.
int wholeUnits(int quantity) {
  final whole = (quantity.abs() + quantityScale ~/ 2) ~/ quantityScale;
  return quantity < 0 ? -whole : whole;
}

final _scale = BigInt.from(quantityScale);
final _max = BigInt.from(maxQuantity);
