/// Sums typed on the amount keys, such as `12+3×4−5÷2`, worked out
/// exactly (no doubles) and checked as an amount.
library;

import 'amount_parser.dart';

/// An exact fraction: what a sum comes to before it is an amount.
final class Fraction {
  Fraction._(this.numerator, this.denominator);

  /// [numerator] / [denominator] in lowest terms, the sign on top.
  factory Fraction(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) {
      throw ArgumentError.value(denominator, 'denominator', 'is zero');
    }
    var n = numerator;
    var d = denominator;
    if (d.isNegative) {
      n = -n;
      d = -d;
    }
    final gcd = n.gcd(d);
    return gcd <= BigInt.one
        ? Fraction._(n, d)
        : Fraction._(n ~/ gcd, d ~/ gcd);
  }

  final BigInt numerator;
  final BigInt denominator;

  bool get isNegative => numerator.isNegative;

  Fraction operator +(Fraction o) => Fraction(
    numerator * o.denominator + o.numerator * denominator,
    denominator * o.denominator,
  );

  Fraction operator -(Fraction o) => Fraction(
    numerator * o.denominator - o.numerator * denominator,
    denominator * o.denominator,
  );

  Fraction operator *(Fraction o) =>
      Fraction(numerator * o.numerator, denominator * o.denominator);

  /// Null when [o] is zero.
  Fraction? divide(Fraction o) => o.numerator == BigInt.zero
      ? null
      : Fraction(numerator * o.denominator, denominator * o.numerator);

  /// The nearest double, for a place that still works in doubles.
  double toDouble() => numerator / denominator;

  /// Minor units of a currency with [scale] decimals, rounded half away
  /// from zero: 7/2 with 0 is 4, 1/3 with 2 is 33.
  BigInt toMinor(int scale) {
    final scaled = numerator.abs() * BigInt.from(10).pow(scale);
    var units = scaled ~/ denominator;
    if (scaled.remainder(denominator) * BigInt.two >= denominator) {
      units += BigInt.one;
    }
    return numerator.isNegative ? -units : units;
  }

  @override
  bool operator ==(Object other) =>
      other is Fraction &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => '$numerator/$denominator';
}

/// The operations of the amount keys.
const sumOperators = '+−×÷';

/// What [expression] comes to, × and ÷ before + and −, equal ranks left
/// to right: `12+3×4−5÷2` is 43/2. An empty expression is 0. Null for
/// one that cannot be read (`5+`, `+5`, `1..2`) or divides by zero.
Fraction? evaluateSum(String expression) => switch (_work(expression)) {
  (final Fraction value, _) => value,
  _ => null,
};

/// [expression] as an amount in minor units of a currency with [scale]
/// decimals, rounded half away from zero (10÷3 NT$ is 3). Refused with
/// its reason when it cannot be read, divides by zero, comes to less
/// than zero or more than [maxAmountUnits]; [AmountRefused.cameTo] then
/// holds the rounded value where there is one.
AmountResult evaluateAmount(String expression, {required int scale}) {
  final (value, problem) = _work(expression);
  if (value == null) return AmountRefused(problem!);
  final minor = value.toMinor(scale);
  if (minor.isNegative) {
    return AmountRefused(AmountProblem.negative, cameTo: minor);
  }
  if (minor > BigInt.from(maxMinorUnits(scale))) {
    return AmountRefused(AmountProblem.tooLarge, cameTo: minor);
  }
  return AmountOk(minor.toInt());
}

(Fraction?, AmountProblem?) _work(String expression) {
  if (expression.isEmpty) return (Fraction(BigInt.zero, BigInt.one), null);
  final tokens = <String>[];
  final number = StringBuffer();
  for (final char in expression.split('')) {
    if (sumOperators.contains(char)) {
      if (number.isEmpty) return (null, AmountProblem.notANumber);
      tokens
        ..add(number.toString())
        ..add(char);
      number.clear();
    } else {
      number.write(char);
    }
  }
  if (number.isEmpty) return (null, AmountProblem.notANumber);
  tokens.add(number.toString());
  final terms = <Fraction>[];
  final signs = <String>[];
  var current = _operand(tokens.first);
  if (current == null) return (null, AmountProblem.notANumber);
  for (var i = 1; i < tokens.length; i += 2) {
    final op = tokens[i];
    final value = _operand(tokens[i + 1]);
    if (value == null) return (null, AmountProblem.notANumber);
    if (op == '×') {
      current = current! * value;
    } else if (op == '÷') {
      current = current!.divide(value);
      if (current == null) return (null, AmountProblem.divisionByZero);
    } else {
      terms.add(current!);
      signs.add(op);
      current = value;
    }
  }
  terms.add(current!);
  var result = terms.first;
  for (var i = 0; i < signs.length; i++) {
    result = signs[i] == '+' ? result + terms[i + 1] : result - terms[i + 1];
  }
  return (result, null);
}

// A number on the keys: digits with at most one point, `0.` and `.5`
// included, and no more than 40 characters.
final _operandPattern = RegExp(r'^(\d*)(?:\.(\d*))?$');

Fraction? _operand(String text) {
  if (text.length > 40) return null;
  final match = _operandPattern.firstMatch(text);
  if (match == null) return null;
  final whole = match[1]!;
  final fraction = match[2] ?? '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  return Fraction(
    BigInt.parse('0$whole$fraction'),
    BigInt.from(10).pow(fraction.length),
  );
}
