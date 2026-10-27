import 'package:expense_tracker/src/core/ui/amount_keys.dart';
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
}
