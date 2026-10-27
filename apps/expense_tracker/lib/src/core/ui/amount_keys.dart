/// Works out `12+3×4−5÷2` with × and ÷ before + and −. Returns null for
/// an expression that cannot be read, such as a trailing operator.
double? evaluate(String expression) {
  final tokens = <String>[];
  final number = StringBuffer();
  for (final char in expression.split('')) {
    if ('+−×÷'.contains(char)) {
      if (number.isEmpty) return null;
      tokens
        ..add(number.toString())
        ..add(char);
      number.clear();
    } else {
      number.write(char);
    }
  }
  if (number.isEmpty) return tokens.isEmpty ? 0 : null;
  tokens.add(number.toString());
  final terms = <double>[];
  final signs = <String>[];
  final first = double.tryParse(tokens.first);
  if (first == null) return null;
  var current = first;
  for (var i = 1; i < tokens.length; i += 2) {
    final op = tokens[i];
    final value = double.tryParse(tokens[i + 1]);
    if (value == null) return null;
    if (op == '×') {
      current = current * value;
    } else if (op == '÷') {
      if (value == 0) return null;
      current = current / value;
    } else {
      terms.add(current);
      signs.add(op);
      current = value;
    }
  }
  terms.add(current);
  var result = terms.first;
  for (var i = 0; i < signs.length; i++) {
    result = signs[i] == '+' ? result + terms[i + 1] : result - terms[i + 1];
  }
  return result;
}

/// What the amount keys have typed so far: digits and the four
/// operations, worked out as they are typed. Shared by the calculator
/// sheet and the keys in 記一筆.
final class AmountKeys {
  AmountKeys([this.expression = '', {this.decimal = false}]);

  /// What was typed, such as `120+35`.
  String expression;

  /// Whether the amount takes two decimals, such as a US$ amount or a
  /// share price.
  final bool decimal;

  static final _trailing = RegExp('[+−×÷]+\$');
  static final _operators = RegExp('[+−×÷]');

  /// Whether a sum is being typed rather than a plain number.
  bool get working => expression.contains(_operators);

  /// What the expression comes to so far; null while it cannot be read.
  double? get value => evaluate(expression);

  /// The amount to keep: a sum left open, such as 120+, counts what was
  /// typed; whole units, or two decimals with [decimal].
  num get result {
    final worked = evaluate(expression.replaceAll(_trailing, '')) ?? 0;
    return decimal
        ? double.parse(worked.clamp(0, 99999999).toStringAsFixed(2))
        : worked.round().clamp(0, 999999999);
  }

  /// Takes one key: a digit, `00`, `000`, `.`, an operation, `C` to clear
  /// or `⌫` to take back the last.
  void press(String key) {
    switch (key) {
      case 'C':
        expression = '';
      case '⌫':
        if (expression.isNotEmpty) {
          expression = expression.substring(0, expression.length - 1);
        }
      case '+' || '−' || '×' || '÷':
        if (expression.isEmpty) return;
        final last = expression[expression.length - 1];
        final trimmed = '+−×÷'.contains(last)
            ? expression.substring(0, expression.length - 1)
            : expression;
        expression = '$trimmed$key';
      case '.':
        // One point to a number, and only where decimals are kept.
        final number = expression.split(_operators).last;
        if (!decimal || number.contains('.')) return;
        expression += number.isEmpty ? '0.' : '.';
      default:
        if (expression.length < 18) expression += key;
    }
  }
}
