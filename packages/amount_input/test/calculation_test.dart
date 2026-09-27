import 'package:amount_input/amount_input.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  final usd = Currency('USD', 2);
  Matcher inputError(AmountInputError code) =>
      throwsA(isA<AmountInputException>().having((e) => e.code, 'code', code));
  test('precedence, unary signs and left associative operations are exact', () {
    final cases = {
      '120 + 85 - 20': 18500,
      '2+3*4': 1400,
      '(2+3)×4': 2000,
      '-2*-3': 600,
      '--2': 200,
      '1--2': 300,
      '1+-2': -100,
      '20/4/2': 250,
      '20−4-2': 1400,
      '0.1+0.2': 30,
      '1÷3*3': 100,
    };
    for (final c in cases.entries) {
      final r = calculateAmount(usd, c.key);
      expect(r.money.minorUnits, BigInt.from(c.value), reason: c.key);
      expect(r.rounded, isFalse, reason: c.key);
    }
  });
  test('percentage is postfix division by one hundred in every context', () {
    for (final c in {
      '50%': 50,
      '100+10%': 10010,
      '100*(1-10%)': 9000,
      '(40+60)%': 100,
      '10%*10%': 1,
      '-50%': -50,
    }.entries) {
      expect(
        calculateAmount(usd, c.key).money.minorUnits,
        BigInt.from(c.value),
        reason: c.key,
      );
    }
  });
  test('leading zeros, decimal points and ASCII spacing require explicit calculation', () {
    for (final c in {
      '00012.50': 1250,
      '.5': 50,
      '1.': 100,
      '+000.5': 50,
      '0000.000': 0,
      '\t 1 +\n 2 \r': 300,
    }.entries) {
      expect(
        calculateAmount(usd, c.key).money.minorUnits,
        BigInt.from(c.value),
      );
    }
    expect(() => Money.parse(usd, '1.'), throwsA(isA<MoneyException>()));
    expect(() => Money.parse(usd, '1.000'), throwsA(isA<MoneyException>()));
  });
  test(
    'only the final denomination boundary rounds and reports precision loss',
    () {
      for (final c in {
        '0.005': 1,
        '-0.005': -1,
        '0.0049': 0,
        '-0.0049': 0,
        '1/3': 33,
        '1.995': 200,
      }.entries) {
        final r = calculateAmount(usd, c.key);
        expect(r.money.minorUnits, BigInt.from(c.value));
        expect(r.rounded, isTrue);
      }
      final r = calculateAmount(usd, '1/3+1/3+1/3');
      expect(r.money.majorText, '1.00');
      expect(r.rounded, isFalse);
      expect(calculateAmount(Currency('JPY', 0), '5/2').money.majorText, '3');
      expect(
        calculateAmount(Currency('KWD', 3), '1/8').money.majorText,
        '0.125',
      );
      expect(
        calculateAmount(Currency('XXX', 18), '1/8').money.majorText,
        '0.125000000000000000',
      );
    },
  );
  test(
    'zero denominators are rejected even inside computed subexpressions',
    () {
      for (final text in ['1/0', '1/-0', '0/0', '1/(2-2)', '1/0%']) {
        expect(
          () => calculateAmount(usd, text),
          inputError(AmountInputError.divisionByZero),
        );
      }
    },
  );
  test('rejects partial, ambiguous, executable and non-supported notation', () {
    for (final text in [
      '',
      ' ',
      '1 2',
      '2(3)',
      '(2',
      '2)',
      '.',
      '..1',
      '1..2',
      '1***2',
      '2//2',
      '10%%',
      '1e2',
      'NaN',
      'Infinity',
      '١٢',
      '１２',
      '2^3',
      '1,000',
      'sqrt(2)',
      '1+',
      '**',
      '1\u0000+2',
    ]) {
      expect(
        () => calculateAmount(usd, text),
        inputError(AmountInputError.syntax),
        reason: text,
      );
    }
  });
  test('length, token and nesting budgets fail with bounded work', () {
    expect(calculateAmount(usd, ' ' * 127 + '1').money.majorText, '1.00');
    expect(
      calculateAmount(usd, '(' * 16 + '1' + ')' * 16).money.majorText,
      '1.00',
    );
    expect(
      calculateAmount(usd, List.filled(48, '1').join('+')).money.majorText,
      '48.00',
    );
    for (final text in [
      '1' * 129,
      '(' * 17 + '1' + ')' * 17,
      List.filled(49, '1').join('+'),
      '+' * 96 + '1',
    ]) {
      expect(
        () => calculateAmount(usd, text),
        inputError(AmountInputError.complexity),
      );
    }
  });
  test(
    'signed storage boundaries are checked after exact final arithmetic',
    () {
      expect(
        calculateAmount(usd, '92233720368547758.07').money.minorUnits,
        Money.maxMinorUnits,
      );
      expect(
        calculateAmount(usd, '-92233720368547758.08').money.minorUnits,
        Money.minMinorUnits,
      );
      expect(
        calculateAmount(usd, '92233720368547758.07*2/2').money.minorUnits,
        Money.maxMinorUnits,
      );
      expect(
        calculateAmount(usd, '92233720368547758.074').money.minorUnits,
        Money.maxMinorUnits,
      );
      for (final text in [
        '92233720368547758.07+.01',
        '-92233720368547758.08-.01',
        '92233720368547758.075',
      ]) {
        expect(
          () => calculateAmount(usd, text),
          throwsA(
            isA<MoneyException>().having(
              (e) => e.code,
              'code',
              MoneyError.overflow,
            ),
          ),
        );
      }
    },
  );
  test('fraction cancellation preserves independent integer arithmetic across a corpus', () {
    for (var a = -75; a <= 75; a++) {
      for (final b in [3, 7, 13]) {
        final r = calculateAmount(usd, '($a/$b)*$b+0.1+0.2');
        expect(r.money.minorUnits, BigInt.from(a * 100 + 30));
        expect(r.rounded, isFalse);
      }
    }
  });
}
