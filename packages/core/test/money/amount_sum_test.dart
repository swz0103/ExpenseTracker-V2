import 'package:core/money/amount_parser.dart';
import 'package:core/money/amount_sum.dart';
import 'package:test/test.dart';

void main() {
  Fraction f(int n, [int d = 1]) => Fraction(BigInt.from(n), BigInt.from(d));

  group('evaluateSum', () {
    test('x and / before + and -, equal ranks left to right', () {
      // 3 x 4 = 12; 5 / 2 = 5/2; 12 + 12 - 5/2 = 43/2.
      expect(evaluateSum('12+3×4−5÷2'), f(43, 2));
      expect(evaluateSum('2+3×4'), f(14));
      expect(evaluateSum('10−4÷2'), f(8));
      // (100 / 4) / 5 = 5.
      expect(evaluateSum('100÷4÷5'), f(5));
    });
    test('exactly, with no doubles', () {
      // 0.1 + 0.2 = 3/10 exactly.
      expect(evaluateSum('0.1+0.2'), f(3, 10));
      expect(evaluateSum('.5'), f(1, 2));
      expect(evaluateSum('0.'), f(0));
    });
    test('nothing is zero; what cannot be read is null', () {
      expect(evaluateSum(''), f(0));
      expect(evaluateSum('5+'), isNull);
      expect(evaluateSum('+5'), isNull);
      expect(evaluateSum('1..2'), isNull);
      expect(evaluateSum('.'), isNull);
      expect(evaluateSum('5÷0'), isNull);
    });
  });

  group('evaluateAmount', () {
    AmountResult twd(String e) => evaluateAmount(e, scale: 0);
    AmountResult usd(String e) => evaluateAmount(e, scale: 2);

    test('rounds to the currency half away from zero', () {
      // 7 / 2 = 3.5 -> 4; 10 / 3 = 3.33 -> 3.
      expect(twd('7÷2'), const AmountOk(4));
      expect(twd('10÷3'), const AmountOk(3));
      // 10 / 3 = 3.333... -> 3.33 US$ = 333 cents.
      expect(usd('10÷3'), const AmountOk(333));
      expect(usd('0.1+0.2'), const AmountOk(30));
    });
    test('5÷0 divides by zero', () {
      expect(twd('5÷0'), const AmountRefused(AmountProblem.divisionByZero));
    });
    test('12−20 comes to -8, which is refused, not kept as 0', () {
      expect(
        twd('12−20'),
        AmountRefused(AmountProblem.negative, cameTo: BigInt.from(-8)),
      );
    });
    test('past 999,999,999 is refused, not cut down to it', () {
      expect(twd('999999999'), const AmountOk(999999999));
      expect(
        twd('1234567890'),
        AmountRefused(AmountProblem.tooLarge, cameTo: BigInt.from(1234567890)),
      );
      // 999,999,999 x 999,999,999 does not overflow.
      expect(
        (twd('999999999×999999999') as AmountRefused).problem,
        AmountProblem.tooLarge,
      );
    });
    test('an open sum cannot be read', () {
      expect(twd('5+'), const AmountRefused(AmountProblem.notANumber));
      expect(twd(''), const AmountOk(0));
    });
  });

  test('Fraction keeps lowest terms and the sign on top', () {
    expect(Fraction(BigInt.from(2), BigInt.from(-4)), f(-1, 2));
    expect(f(1, 3).toMinor(2), BigInt.from(33));
    expect(f(-7, 2).toMinor(0), BigInt.from(-4));
    expect(f(1, 2).toDouble(), 0.5);
    expect(f(1, 2).toString(), '1/2');
    expect(() => f(1, 0), throwsArgumentError);
  });
}
