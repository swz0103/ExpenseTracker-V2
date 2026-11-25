import 'package:core/money/typed_text.dart' show halfWidth;

/// The broker's discount on the fee, in basis points of the full fee:
/// 10000 for none, 6000 for 6折 (0.6), 2800 for 2.8折 (0.28). The one
/// range every discount is checked against (D7): more than nothing, at
/// most the full fee.
abstract final class BrokerDiscountRange {
  /// The smallest discount kept: one basis point of the full fee.
  static const lowest = 1;

  /// No discount: the full fee.
  static const highest = 10000;

  /// Whether [basisPoints] is a discount a fee may be charged at.
  static bool holds(int basisPoints) =>
      basisPoints >= lowest && basisPoints <= highest;

  /// [basisPoints] brought into the range.
  static int clamp(int basisPoints) =>
      basisPoints.clamp(lowest, highest).toInt();
}

/// What a discount typed by a person reads as.
sealed class DiscountReading {
  const DiscountReading();
}

/// A discount in the range, in basis points of the full fee.
final class DiscountRead extends DiscountReading {
  const DiscountRead(this.basisPoints);

  final int basisPoints;
}

/// Not a discount: no number, finer than a basis point, or a share of
/// the fee written in 折 (0.6折), which mixes the two ways of writing it
/// (D86): 6折 and 0.6 are the same discount, 0.6折 is neither.
final class DiscountUnreadable extends DiscountReading {
  const DiscountUnreadable();
}

/// A number, but none a fee is charged at: nothing, or more than the full
/// fee.
final class DiscountOutOfRange extends DiscountReading {
  const DiscountOutOfRange();
}

/// The unit a broker writes a discount in: 6折 is 0.6 of the fee.
const discountUnit = '折';

/// Basis points of the full fee in one [discountUnit]: a tenth of it.
const _perUnit = BrokerDiscountRange.highest ~/ 10;

/// Reads a discount as a person types it: a share of the full fee (0.6,
/// .28, 1) or in 折 (6折, 2.8 折, 10折). Spaces are ignored, and
/// full-width digits read as their ASCII forms ([halfWidth]). Less than
/// one 折 but more than none (0.6折) is [DiscountUnreadable]: it would
/// be a tenth of what was meant.
DiscountReading readBrokerDiscount(String text) {
  var number = halfWidth(text).replaceAll(' ', '');
  final inUnit = number.endsWith(discountUnit);
  if (inUnit) number = number.substring(0, number.length - 1);
  final match = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(number);
  if (match == null || number.isEmpty || number == '.') {
    return const DiscountUnreadable();
  }
  final whole = match.group(1) ?? '';
  final fraction = (match.group(2) ?? '').replaceFirst(RegExp(r'0+$'), '');
  // A share of the fee has four places to a basis point; 折 has three.
  final places = inUnit ? 3 : 4;
  if (fraction.length > places) return const DiscountUnreadable();
  // More than two whole digits is past any discount, however many.
  if (whole.replaceFirst(RegExp('^0+'), '').length > 2) {
    return const DiscountOutOfRange();
  }
  final basisPoints =
      int.parse(whole.isEmpty ? '0' : whole) *
          (inUnit ? _perUnit : BrokerDiscountRange.highest) +
      int.parse(fraction.padRight(places, '0'));
  // 0.6折 is a share written in 折: neither form, read as neither.
  if (inUnit && basisPoints > 0 && basisPoints < _perUnit) {
    return const DiscountUnreadable();
  }
  return BrokerDiscountRange.holds(basisPoints)
      ? DiscountRead(basisPoints)
      : const DiscountOutOfRange();
}
