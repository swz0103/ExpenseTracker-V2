/// Plain figures for amounts: digits, grouping, decimals and signs. No
/// words and no currency names; how the app shows an amount is decided
/// in its design system, on top of these.
library;

/// `1234567` → `1,234,567`; negatives keep a plain `-`: `-1,200`.
String groupDigits(int value) {
  final grouped = _group(value.abs().toString());
  return value < 0 ? '-$grouped' : grouped;
}

/// [minor] units of a currency with [scale] decimals as figures, with
/// all its decimals and a plain `-` when negative: `1,234.50` for 123450
/// US cents, `1,234` for 1234 NT$; with [grouped] false, `1234.50`, as
/// typed into a field.
String figures(int minor, int scale, {bool grouped = true}) {
  final digits = minor.abs().toString().padLeft(scale + 1, '0');
  final split = digits.length - scale;
  final whole = grouped
      ? _group(digits.substring(0, split))
      : digits.substring(0, split);
  final sign = minor < 0 ? '-' : '';
  return scale == 0 ? '$sign$whole' : '$sign$whole.${digits.substring(split)}';
}

/// [value] with [decimals] decimals after rounding half away from zero,
/// and the trailing zeros of the decimals trimmed: `128.5` for 128.5 with
/// 2, `128` for 128.0, `0.3` for 0.30000000000000004, `12.35` for 12.345
/// as written. Grouped like [groupDigits] unless [grouped] is false.
String trimmedDecimals(double value, int decimals, {bool grouped = true}) {
  final scaled = roundHalfAwayFromZero(value, decimals);
  var text = figures(scaled, decimals, grouped: grouped);
  if (decimals > 0) {
    text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  return text == '-0' ? '0' : text;
}

/// [value] with exactly [decimals] decimals, rounded half away from
/// zero: `5.2` for 52000 / 10000 with 1, `-3.00` for -3 with 2.
String fixedDecimals(double value, int decimals, {bool grouped = false}) {
  final text = figures(
    roundHalfAwayFromZero(value, decimals),
    decimals,
    grouped: grouped,
  );
  return RegExp(r'^-[0.,]+$').hasMatch(text) ? text.substring(1) : text;
}

/// [value] times 10^[decimals] as a whole number, half away from zero,
/// from the shortest decimal that names the double: 1.005 with 2 is 101
/// (a double holds 1.005 as 1.00499...), 2.5 with 0 is 3, -2.5 is -3.
int roundHalfAwayFromZero(double value, int decimals) {
  if (value.isNaN || value.isInfinite) {
    throw ArgumentError.value(value, 'value', 'not a finite number');
  }
  final written = value.abs().toString();
  // Exponent forms (1e-7, 1.5e+21) are rare for amounts; work them out
  // through the double itself.
  if (written.contains('e')) {
    final scaled = (value.abs() * _pow10(decimals)).round();
    return value < 0 ? -scaled : scaled;
  }
  final parts = written.split('.');
  final fraction = parts.length > 1 ? parts[1] : '';
  final kept = fraction.length > decimals
      ? fraction.substring(0, decimals)
      : fraction.padRight(decimals, '0');
  var scaled = BigInt.parse('${parts[0]}$kept');
  if (fraction.length > decimals &&
      fraction.codeUnitAt(decimals) >= '5'.codeUnitAt(0)) {
    scaled += BigInt.one;
  }
  return value < 0 ? -scaled.toInt() : scaled.toInt();
}

/// A signed value as its sign and its size, for a place that writes the
/// sign its own way: `(-1, 200)` for -200, `(0, 0)` for 0.
({int sign, int size}) splitSign(int value) =>
    (sign: value.sign, size: value.abs());

String _group(String digits) {
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return grouped.toString();
}

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
