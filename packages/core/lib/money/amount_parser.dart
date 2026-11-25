/// Reading amounts that people type or import: the one parser of the app.
///
/// Amounts are `int` minor units of a currency whose decimals ([scale])
/// the caller knows, such as 2 for US cents and 0 for New Taiwan dollars.
library;

/// The largest amount the app accepts, in whole units of any currency:
/// 999,999,999 (and for a currency with decimals, up to .99 more).
const maxAmountUnits = 999999999;

/// The largest number of minor units the app accepts in a currency with
/// [scale] decimals: 999,999,999 for New Taiwan dollars, 99,999,999,999
/// for US cents.
int maxMinorUnits(int scale) => (maxAmountUnits + 1) * _pow10(scale) - 1;

/// Why a text or a sum is not an amount.
enum AmountProblem {
  /// Nothing was written.
  empty,

  /// Not a number, such as `abc`, `.5`, `1 200` or `5+`.
  notANumber,

  /// More decimals than the currency has, such as `12.345` US dollars,
  /// where the parser is not asked to round.
  tooManyDecimals,

  /// Above [maxAmountUnits].
  tooLarge,

  /// Could be read in more than one way, such as `1.234,50` or, for a
  /// currency without decimals, `12.345`.
  ambiguous,

  /// A sum divides by zero.
  divisionByZero,

  /// A sum comes to less than zero where only amounts of zero or more
  /// are taken.
  negative,
}

/// What a text or a sum comes to: an amount, or why it is not one.
sealed class AmountResult {
  const AmountResult();

  /// The amount in minor units, or null when there is none.
  int? get minorOrNull => switch (this) {
    AmountOk(:final minor) => minor,
    AmountRefused() => null,
  };
}

/// An amount in minor units.
final class AmountOk extends AmountResult {
  const AmountOk(this.minor);

  final int minor;

  @override
  bool operator ==(Object other) => other is AmountOk && other.minor == minor;

  @override
  int get hashCode => minor.hashCode;

  @override
  String toString() => 'AmountOk($minor)';
}

/// Not an amount, and why. [cameTo] is what a sum came to in minor units
/// (rounded as an amount is) when it has a value that is refused, such
/// as -800 for 12−20 or 1234567890 past the limit; null otherwise.
final class AmountRefused extends AmountResult {
  const AmountRefused(this.problem, {this.cameTo});

  final AmountProblem problem;
  final BigInt? cameTo;

  @override
  bool operator ==(Object other) =>
      other is AmountRefused &&
      other.problem == problem &&
      other.cameTo == cameTo;

  @override
  int get hashCode => Object.hash(problem, cameTo);

  @override
  String toString() =>
      'AmountRefused(${problem.name}${cameTo == null ? '' : ', $cameTo'})';
}

/// How [parseAmount] treats more decimals than the currency has.
enum Decimals {
  /// More decimals than the currency has are refused
  /// ([AmountProblem.tooManyDecimals]) unless they are all zeros:
  /// `80000.0` is 80000 NT$, `12.5` NT$ is refused.
  exact,

  /// More decimals are rounded half away from zero from the digits as
  /// written: `12.345` US$ is 1235 cents (a double would hold 12.345 as
  /// 12.3449...).
  round,
}

/// [text] as minor units of a currency with [scale] decimals.
///
/// Takes an optional leading `-`, `−` (U+2212) or `+`; digits, grouped
/// by commas only in groups of three (`1,234,567`); and decimals after a
/// `.`. Space around the number is ignored, space inside it is not.
/// Never throws: anything else is an [AmountRefused] with its reason.
AmountResult parseAmount(
  String text, {
  required int scale,
  Decimals decimals = Decimals.exact,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const AmountRefused(AmountProblem.empty);
  // Measured before any pattern: a pattern run over millions of
  // characters overflows the stack.
  if (trimmed.length > _maxLength) {
    final numeric = trimmed.codeUnits.every(
      (unit) =>
          (unit >= _zero && unit <= _nine) || unit == _comma || unit == _dot,
    );
    return AmountRefused(
      numeric ? AmountProblem.tooLarge : AmountProblem.notANumber,
    );
  }
  var body = trimmed;
  var negative = false;
  if (body.startsWith('-') || body.startsWith('−')) {
    negative = true;
    body = body.substring(1);
  } else if (body.startsWith('+')) {
    body = body.substring(1);
  }
  final match = _number.firstMatch(body);
  if (match == null) {
    return AmountRefused(_whyNot(body, scale));
  }
  final whole = match[1]!;
  final fraction = match[2] ?? '';
  // 12.345 with no decimals in the currency reads as twelve thousand
  // with a dot between thousands as well as as twelve.
  if (scale == 0 && fraction.length == 3 && !whole.contains(',')) {
    return const AmountRefused(AmountProblem.ambiguous);
  }
  final digits = whole.replaceAll(',', '');
  if (digits.length > _maxDigits) {
    return const AmountRefused(AmountProblem.tooLarge);
  }
  final kept = fraction.length > scale
      ? fraction.substring(0, scale)
      : fraction.padRight(scale, '0');
  final dropped = fraction.length > scale ? fraction.substring(scale) : '';
  var size = BigInt.parse('$digits$kept');
  if (dropped.contains(RegExp('[1-9]'))) {
    if (decimals == Decimals.exact) {
      return const AmountRefused(AmountProblem.tooManyDecimals);
    }
    if (dropped.codeUnitAt(0) >= _five) size += BigInt.one;
  }
  if (size > BigInt.from(maxMinorUnits(scale))) {
    return const AmountRefused(AmountProblem.tooLarge);
  }
  final minor = size.toInt();
  return AmountOk(negative ? -minor : minor);
}

/// A decimal written as data is stored, such as a share price of
/// `128.50`: digits, an optional `-` and `.` decimals, nothing else.
/// Null for anything else. For prices and rates kept as doubles, not
/// for amounts people type ([parseAmount]).
double? parseDecimal(String text) {
  if (text.length > 40 || !_decimal.hasMatch(text)) return null;
  return double.parse(text);
}

final _decimal = RegExp(r'^-?[0-9]+(\.[0-9]+)?$');

// Digits, grouped in threes or not at all, and optional decimals
// (`12.` is twelve, as a field may hold it while typing).
final _number = RegExp(r'^(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d*))?$');

/// Why [body] (without its sign) does not match [_number].
AmountProblem _whyNot(String body, int scale) {
  final comma = body.indexOf(',');
  final dot = body.indexOf('.');
  // 1.234,50 or 12,50: a comma for the decimals.
  if (comma >= 0 && (dot < 0 || dot < comma)) {
    if (RegExp(r'^[\d.,]+$').hasMatch(body)) return AmountProblem.ambiguous;
  }
  return AmountProblem.notANumber;
}

// More digits than any amount within [maxAmountUnits] has, so BigInt
// never works on long input.
const _maxDigits = 20;

// The longest text read as an amount: room for the largest amount,
// grouped, with a sign and more decimals than any currency has; a longer
// one is refused before it is matched.
const _maxLength = 64;
final _zero = '0'.codeUnitAt(0);
final _nine = '9'.codeUnitAt(0);
final _comma = ','.codeUnitAt(0);
final _dot = '.'.codeUnitAt(0);
final _five = '5'.codeUnitAt(0);

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
