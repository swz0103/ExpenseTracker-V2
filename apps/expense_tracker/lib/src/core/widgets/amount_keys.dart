import 'package:core/money/amount_parser.dart';
import 'package:core/money/amount_sum.dart';

export 'package:core/money/amount_parser.dart' show AmountResult;

/// Works out `12+3×4−5÷2` with × and ÷ before + and −. Returns null for
/// an expression that cannot be read, such as a trailing operator, or
/// one that divides by zero. Worked out exactly; the double is only the
/// nearest to the exact value.
double? evaluate(String expression) => evaluateSum(expression)?.toDouble();

/// What the amount keys have typed so far: digits and the four
/// operations, worked out as they are typed. Shared by the calculator
/// sheet and the keys in 記一筆.
final class AmountKeys {
  AmountKeys(this.expression, {this.decimal = false});

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

  /// The decimals the amount is kept to.
  int get scale => decimal ? 2 : 0;

  /// The amount to keep, in minor units of [scale] (whole NT$, or
  /// cents with [decimal]), or why there is none: a sum left open, such
  /// as 120+, counts what was typed; one that divides by zero, comes to
  /// less than zero or more than 999,999,999 is refused, never changed
  /// into another amount.
  AmountResult get amount =>
      evaluateAmount(expression.replaceAll(_trailing, ''), scale: scale);

  /// [amount] for a caller that cannot refuse: whole units, or two
  /// decimals with [decimal]; a refused amount becomes 0, or the limit
  /// when it is too large. The calculator sheet uses [amount] instead,
  /// so what it shows is what it keeps.
  num get result {
    final minor = switch (amount) {
      AmountOk(:final minor) => minor,
      AmountRefused(problem: AmountProblem.tooLarge) => maxMinorUnits(scale),
      AmountRefused() => 0,
    };
    return decimal ? minor / 100 : minor;
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
