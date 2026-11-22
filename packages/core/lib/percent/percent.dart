/// Ratios and percentages, with one rounding policy for all of them:
/// half away from zero (2.5 → 3, -2.5 → -3), worked out exactly on
/// whole numbers where the inputs are whole.
library;

import '../money/amount_format.dart' show roundHalfAwayFromZero;

/// [numerator] / [denominator] rounded half away from zero: 7 / 2 → 4,
/// -7 / 2 → -4, 10 / 3 → 3. Throws on a zero [denominator].
int divideRounded(int numerator, int denominator) {
  if (denominator == 0) {
    throw ArgumentError.value(denominator, 'denominator', 'is zero');
  }
  final negative = (numerator < 0) != (denominator < 0);
  final n = numerator.abs();
  final d = denominator.abs();
  var quotient = n ~/ d;
  if ((n % d) * 2 >= d) quotient += 1;
  return negative ? -quotient : quotient;
}

/// [part] of [whole] as a whole percent: 1 of 3 → 33, 1 of 8 → 13
/// (12.5 rounds up), 50174 of 50000 → 100. 0 when [whole] is 0.
///
/// A rounded percent is for showing. Whether [part] is over [whole] is
/// [isOver], never `percent > 100`.
int percent(int part, int whole) =>
    whole == 0 ? 0 : divideRounded(part * 100, whole);

/// [part] of [whole] as a percent in tenths, for one decimal: 9 of 1000
/// → 9 (0.9%), 1 of 3 → 333 (33.3%), -1 of 8 → -125 (-12.5%). 0 when
/// [whole] is 0.
int percentTenths(int part, int whole) =>
    whole == 0 ? 0 : divideRounded(part * 1000, whole);

/// A ratio held as a double (0.1234 for 12.34%) as a percent in tenths,
/// half away from zero from the ratio as written: 0.1234 → 123,
/// -0.00949 → -9, 0.0125 → 13.
int ratioTenths(double ratio) => roundHalfAwayFromZero(ratio * 100, 1);

/// Whether [part] is strictly more than [whole]: 50,174 spent of a
/// 50,000 budget is over, though its rounded percent is 100.
bool isOver(int part, int whole) => part > whole;
