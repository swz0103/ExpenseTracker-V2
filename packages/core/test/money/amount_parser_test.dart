import 'package:core/money/amount_parser.dart';
import 'package:test/test.dart';

void main() {
  AmountResult twd(String text, [Decimals d = Decimals.exact]) =>
      parseAmount(text, scale: 0, decimals: d);
  AmountResult usd(String text, [Decimals d = Decimals.exact]) =>
      parseAmount(text, scale: 2, decimals: d);
  AmountRefused no(AmountProblem p) => AmountRefused(p);

  group('the limit', () {
    test('is 999,999,999 whole units in every currency', () {
      expect(maxAmountUnits, 999999999);
      // (999,999,999 + 1) x 10^0 - 1.
      expect(maxMinorUnits(0), 999999999);
      // (999,999,999 + 1) x 10^2 - 1 = 99,999,999,999 cents.
      expect(maxMinorUnits(2), 99999999999);
    });
    test('is taken and one more is refused', () {
      expect(twd('999,999,999'), const AmountOk(999999999));
      expect(twd('1,000,000,000'), no(AmountProblem.tooLarge));
      expect(usd('999999999.99'), const AmountOk(99999999999));
      expect(usd('1000000000'), no(AmountProblem.tooLarge));
      expect(twd('-999999999'), const AmountOk(-999999999));
      expect(twd('-1000000000'), no(AmountProblem.tooLarge));
    });
    test('very long digits are too large, never an exception', () {
      expect(twd('99999999999999999999'), no(AmountProblem.tooLarge));
      expect(twd('9' * 500), no(AmountProblem.tooLarge));
    });
    test('rounding up past the limit is too large', () {
      // 999,999,999.995 rounds to 1,000,000,000.00.
      expect(usd('999999999.995', Decimals.round), no(AmountProblem.tooLarge));
    });
  });

  group('plain amounts', () {
    test('digits, with or without decimals', () {
      expect(twd('180'), const AmountOk(180));
      expect(usd('12.5'), const AmountOk(1250));
      expect(usd('12.50'), const AmountOk(1250));
      expect(usd('12'), const AmountOk(1200));
      expect(usd('0.07'), const AmountOk(7));
      expect(twd('0'), const AmountOk(0));
    });
    test('a point with nothing after it, as while typing', () {
      expect(twd('12.'), const AmountOk(12));
      expect(usd('12.'), const AmountOk(1200));
    });
    test('space around the number is ignored', () {
      expect(twd('  180 '), const AmountOk(180));
    });
    test('thousands commas in groups of three', () {
      expect(twd('80,000'), const AmountOk(80000));
      expect(twd('1,234,567'), const AmountOk(1234567));
      expect(usd('1,234.50'), const AmountOk(123450));
    });
  });

  group('signs', () {
    test('-, the true minus and + are read', () {
      expect(twd('-300'), const AmountOk(-300));
      expect(twd('−300'), const AmountOk(-300));
      expect(twd('+300'), const AmountOk(300));
      expect(usd('-12.5'), const AmountOk(-1250));
    });
    test('a sign alone or doubled is not a number', () {
      expect(twd('-'), no(AmountProblem.notANumber));
      expect(twd('--5'), no(AmountProblem.notANumber));
      expect(twd('+-5'), no(AmountProblem.notANumber));
    });
  });

  group('exact: decimals must fit the currency', () {
    test('a non-zero digit past the currency is refused', () {
      expect(twd('12.5'), no(AmountProblem.tooManyDecimals));
      expect(usd('12.345'), no(AmountProblem.tooManyDecimals));
    });
    test('zeros past the currency are only zeros', () {
      // 80000.0 is 80,000 NT$; 12.500 is 12.50 US$.
      expect(twd('80000.0'), const AmountOk(80000));
      expect(twd('80000.00'), const AmountOk(80000));
      expect(usd('12.500'), const AmountOk(1250));
    });
  });

  group('round: half away from zero from the digits as written', () {
    test('to the currency\'s decimals', () {
      // 12.345 -> 12.35 (the 5 rounds up); 12.344 -> 12.34.
      expect(usd('12.345', Decimals.round), const AmountOk(1235));
      expect(usd('12.344', Decimals.round), const AmountOk(1234));
      // 1.005 -> 1.01, though a double holds 1.005 as 1.00499...
      expect(usd('1.005', Decimals.round), const AmountOk(101));
      // -2.5 NT$ -> -3, away from zero; 2.4 -> 2.
      expect(twd('-2.5', Decimals.round), const AmountOk(-3));
      expect(twd('2.4', Decimals.round), const AmountOk(2));
      expect(twd('0.5', Decimals.round), const AmountOk(1));
    });
  });

  group('what must not be read as something else', () {
    test('a point with no digits before it', () {
      expect(twd('.5'), no(AmountProblem.notANumber));
      expect(twd('-.5'), no(AmountProblem.notANumber));
      expect(usd('.5', Decimals.round), no(AmountProblem.notANumber));
    });
    test('a comma for the decimals', () {
      expect(usd('1.234,50'), no(AmountProblem.ambiguous));
      expect(twd('1.234,50', Decimals.round), no(AmountProblem.ambiguous));
      expect(usd('12,50'), no(AmountProblem.ambiguous));
      expect(twd('1,2345'), no(AmountProblem.ambiguous));
    });
    test('a point between thousands for a currency without decimals', () {
      // 12.345 NT$ could be twelve thousand three hundred and forty-five.
      expect(twd('12.345'), no(AmountProblem.ambiguous));
      expect(twd('12.345', Decimals.round), no(AmountProblem.ambiguous));
      expect(twd('1.000'), no(AmountProblem.ambiguous));
    });
    test('space inside the number', () {
      expect(twd('1 200'), no(AmountProblem.notANumber));
      expect(twd('- 5'), no(AmountProblem.notANumber));
    });
    test('anything else', () {
      expect(twd('abc'), no(AmountProblem.notANumber));
      expect(twd('12a'), no(AmountProblem.notANumber));
      expect(twd('1e5'), no(AmountProblem.notANumber));
      expect(twd('1.2.3'), no(AmountProblem.notANumber));
      expect(twd('0x10'), no(AmountProblem.notANumber));
      expect(twd('１２'), no(AmountProblem.notANumber));
    });
    test('nothing at all', () {
      expect(twd(''), no(AmountProblem.empty));
      expect(twd('   '), no(AmountProblem.empty));
    });
  });

  test('minorOrNull gives the amount or null', () {
    expect(twd('180').minorOrNull, 180);
    expect(twd('x').minorOrNull, isNull);
  });

  group('parseDecimal: decimals as stored', () {
    test('reads plain decimals', () {
      expect(parseDecimal('128.50'), 128.5);
      expect(parseDecimal('12'), 12.0);
      expect(parseDecimal('-0.5'), -0.5);
    });
    test('refuses anything else', () {
      expect(parseDecimal(''), isNull);
      expect(parseDecimal('1,000'), isNull);
      expect(parseDecimal('.5'), isNull);
      expect(parseDecimal('1e3'), isNull);
      expect(parseDecimal('NaN'), isNull);
    });
  });
}
