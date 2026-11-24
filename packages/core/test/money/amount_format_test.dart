import 'package:core/money/amount_format.dart';
import 'package:test/test.dart';

void main() {
  test('groupDigits puts a comma every three digits', () {
    expect(groupDigits(0), '0');
    expect(groupDigits(999), '999');
    expect(groupDigits(1000), '1,000');
    expect(groupDigits(1234567), '1,234,567');
    expect(groupDigits(-1200), '-1,200');
  });

  group('figures', () {
    test('with the currency\'s decimals', () {
      expect(figures(123450, 2), '1,234.50');
      expect(figures(7, 2), '0.07');
      expect(figures(-7, 2), '-0.07');
      expect(figures(1234, 0), '1,234');
      expect(figures(-1234, 0), '-1,234');
    });
    test('plain, as typed into a field', () {
      expect(figures(123450, 2, grouped: false), '1234.50');
      expect(figures(-123450, 2, grouped: false), '-1234.50');
      expect(figures(1234, 0, grouped: false), '1234');
    });
  });

  group('roundHalfAwayFromZero', () {
    test('from the decimal as written', () {
      // 1.005 x 100 = 100.5 -> 101; a double holds 1.005 as 1.00499...
      expect(roundHalfAwayFromZero(1.005, 2), 101);
      // 2.5 -> 3 and -2.5 -> -3: away from zero.
      expect(roundHalfAwayFromZero(2.5, 0), 3);
      expect(roundHalfAwayFromZero(-2.5, 0), -3);
      expect(roundHalfAwayFromZero(2.49, 0), 2);
      // 0.1 + 0.2 = 0.30000000000000004 -> 30 hundredths.
      expect(roundHalfAwayFromZero(0.1 + 0.2, 2), 30);
      expect(roundHalfAwayFromZero(128.5, 0), 129);
    });
    test('in exponent form', () {
      expect(roundHalfAwayFromZero(1e-7, 2), 0);
      expect(roundHalfAwayFromZero(-1e-7, 2), 0);
    });
    test('refuses what is not a number', () {
      expect(() => roundHalfAwayFromZero(double.nan, 2), throwsArgumentError);
    });
  });

  group('trimmedDecimals: up to n decimals, no trailing zeros', () {
    test('keeps real ticks', () {
      expect(trimmedDecimals(128.5, 2), '128.5');
      expect(trimmedDecimals(128.0, 2), '128');
      expect(trimmedDecimals(1234.55, 2), '1,234.55');
      expect(trimmedDecimals(1234.55, 2, grouped: false), '1234.55');
      expect(trimmedDecimals(0.30000000000000004, 2), '0.3');
      // 12.345 -> 12.35 as written.
      expect(trimmedDecimals(12.345, 2), '12.35');
    });
    test('zero and below', () {
      expect(trimmedDecimals(0, 2), '0');
      expect(trimmedDecimals(-0.001, 2), '0');
      expect(trimmedDecimals(-3.5, 2), '-3.5');
    });
  });

  group('fixedDecimals: exactly n decimals', () {
    test('rounds half away from zero', () {
      // 52000 / 10000 = 5.2.
      expect(fixedDecimals(5.2, 1), '5.2');
      expect(fixedDecimals(3, 2), '3.00');
      expect(fixedDecimals(-1.25, 1), '-1.3');
      expect(fixedDecimals(12345.6, 1, grouped: true), '12,345.6');
    });
    test('no minus on a value that rounds to zero', () {
      expect(fixedDecimals(-0.04, 1), '0.0');
    });
  });

  test('splitSign gives the sign and the size', () {
    expect(splitSign(-200), (sign: -1, size: 200));
    expect(splitSign(0), (sign: 0, size: 0));
    expect(splitSign(5), (sign: 1, size: 5));
  });

  test('zero has no sign, at any scale (mutation review 11)', () {
    expect(figures(0, 2), '0.00');
    expect(figures(0, 0), '0');
  });

  test('a value written with an exponent is rounded half away from zero '
      '(mutation review 11)', () {
    // 1e-7 at 7 decimals is 1; 5e-7 at 6 decimals is 0.5, rounded to 1.
    expect(roundHalfAwayFromZero(1e-7, 7), 1);
    expect(roundHalfAwayFromZero(5e-7, 6), 1);
    expect(roundHalfAwayFromZero(-5e-7, 6), -1);
  });
}
