import 'package:foundation_values/foundation_values.dart';

export 'src/split_allocation.dart';

enum AmountInputError { syntax, divisionByZero, complexity }

final class AmountInputException implements Exception {
  const AmountInputException(this.code);
  final AmountInputError code;
  @override
  String toString() => 'AmountInputException(${code.name})';
}

final class AmountCalculation {
  const AmountCalculation._(this.money, this.rounded);
  final Money money;
  final bool rounded;
  static const roundingPolicy = Money.roundingPolicy;
}

/// Evaluates a bounded expression without floating point, eval, or side effects.
/// Percent is postfix division by 100, never a context-dependent surcharge.
/// The caller must explicitly confirm this proposal before replacing input.
AmountCalculation calculateAmount(Currency currency, String expression) {
  if (expression.length > 128) {
    throw const AmountInputException(AmountInputError.complexity);
  }
  final value = _Parser(expression).parse();
  final scaled = value.n * BigInt.from(10).pow(currency.scale);
  return AmountCalculation._(
    Money.quantizeRatio(currency, value.n, value.d),
    scaled.remainder(value.d) != BigInt.zero,
  );
}

final class _Ratio {
  _Ratio(BigInt numerator, BigInt denominator)
    : n = numerator ~/ numerator.gcd(denominator),
      d = denominator ~/ numerator.gcd(denominator) {
    if (n.bitLength > 4096 || d.bitLength > 4096) {
      throw const AmountInputException(AmountInputError.complexity);
    }
  }
  final BigInt n, d;
  _Ratio add(_Ratio b) => _Ratio(n * b.d + b.n * d, d * b.d);
  _Ratio negate() => _Ratio(-n, d);
  _Ratio multiply(_Ratio b) => _Ratio(n * b.n, d * b.d);
  _Ratio divide(_Ratio b) {
    if (b.n == BigInt.zero) {
      throw const AmountInputException(AmountInputError.divisionByZero);
    }
    return _Ratio(b.n.isNegative ? -n * b.d : n * b.d, d * b.n.abs());
  }

  _Ratio percent() => _Ratio(n, d * BigInt.from(100));
}

final class _Parser {
  _Parser(this.text);
  final String text;
  int at = 0, depth = 0, tokens = 0;
  Never invalid() => throw const AmountInputException(AmountInputError.syntax);
  void token() {
    if (++tokens > 96) {
      throw const AmountInputException(AmountInputError.complexity);
    }
  }

  void whitespace() {
    while (at < text.length && ' \t\r\n'.contains(text[at])) {
      at++;
    }
  }

  bool take(String choices) {
    whitespace();
    if (at < text.length && choices.contains(text[at])) {
      at++;
      token();
      return true;
    }
    return false;
  }

  _Ratio parse() {
    final value = sum();
    whitespace();
    if (at != text.length) invalid();
    return value;
  }

  _Ratio sum() {
    var value = product();
    while (true) {
      if (take('+')) {
        value = value.add(product());
      } else if (take('-−')) {
        value = value.add(product().negate());
      } else {
        return value;
      }
    }
  }

  _Ratio product() {
    var value = unary();
    while (true) {
      if (take('*×')) {
        value = value.multiply(unary());
      } else if (take('/÷')) {
        value = value.divide(unary());
      } else {
        return value;
      }
    }
  }

  _Ratio unary() {
    var negative = false;
    while (true) {
      if (take('+')) {
        continue;
      } else if (take('-−')) {
        negative = !negative;
      } else {
        break;
      }
    }
    var value = primary();
    if (take('%')) value = value.percent();
    return negative ? value.negate() : value;
  }

  _Ratio primary() {
    if (take('(')) {
      if (++depth > 16) {
        throw const AmountInputException(AmountInputError.complexity);
      }
      final value = sum();
      if (!take(')')) invalid();
      depth--;
      return value;
    }
    whitespace();
    final start = at;
    bool digit() =>
        at < text.length &&
        text.codeUnitAt(at) >= 48 &&
        text.codeUnitAt(at) <= 57;
    while (digit()) {
      at++;
    }
    var digits = at - start;
    var scale = 0;
    if (at < text.length && text[at] == '.') {
      at++;
      final fractionStart = at;
      while (digit()) {
        at++;
      }
      scale = at - fractionStart;
      digits += scale;
    }
    if (digits == 0) invalid();
    token();
    final coefficient = BigInt.parse(
      text.substring(start, at).replaceAll('.', ''),
    );
    return _Ratio(coefficient, BigInt.from(10).pow(scale));
  }
}
