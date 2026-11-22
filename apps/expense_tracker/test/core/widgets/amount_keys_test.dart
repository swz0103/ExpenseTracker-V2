import 'package:core/money/amount_parser.dart';
import 'package:expense_tracker/src/core/widgets/amount_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AmountKeys typed(List<String> keys, {bool decimal = false}) {
    final pad = AmountKeys('', decimal: decimal);
    keys.forEach(pad.press);
    return pad;
  }

  test('a sum is worked out as it is typed', () {
    final pad = typed(['1', '2', '0', '+', '3', '5']);
    expect(pad.expression, '120+35');
    expect(pad.working, isTrue);
    expect(pad.result, 155);
  });

  test('a sum left open counts what was typed', () {
    expect(typed(['1', '2', '0', '+']).result, 120);
  });

  test('a second operation takes the place of the first', () {
    expect(typed(['9', '+', '−', '4']).expression, '9−4');
    expect(typed(['+']).expression, '');
  });

  test('decimals only where the amount takes them, one to a number', () {
    expect(typed(['1', '.', '5']).expression, '15');
    final cents = typed(['.', '5', '.', '0'], decimal: true);
    expect(cents.expression, '0.50');
    expect(cents.result, 0.5);
  });

  test('⌫ takes back one key and C all', () {
    expect(typed(['1', '2', '⌫']).expression, '1');
    expect(typed(['1', '2', 'C']).expression, '');
  });

  group('ENT-04: amount says what is kept, or why nothing is', () {
    test('an amount in minor units', () {
      // 120 + 35 = 155.
      expect(typed(['1', '2', '0', '+', '3', '5']).amount, const AmountOk(155));
      // 12.5 US$ = 1250 cents.
      expect(
        typed(['1', '2', '.', '5'], decimal: true).amount,
        const AmountOk(1250),
      );
    });
    test('÷0, below zero and past the limit are refused', () {
      expect(
        typed(['5', '÷', '0']).amount,
        const AmountRefused(AmountProblem.divisionByZero),
      );
      expect(
        typed(['1', '2', '−', '2', '0']).amount,
        AmountRefused(AmountProblem.negative, cameTo: BigInt.from(-8)),
      );
      expect(
        (typed('1234567890'.split('')).amount as AmountRefused).problem,
        AmountProblem.tooLarge,
      );
    });
    test('the limit is the same with decimals', () {
      // 999,999,999.99 US$ is taken; 1,000,000,000 is not.
      expect(
        typed('999999999.99'.split(''), decimal: true).amount,
        const AmountOk(99999999999),
      );
      expect(
        (typed('1000000000'.split(''), decimal: true).amount as AmountRefused)
            .problem,
        AmountProblem.tooLarge,
      );
    });
  });
}
