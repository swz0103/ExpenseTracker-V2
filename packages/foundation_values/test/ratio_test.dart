import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  final usd = Currency('USD', 2);
  test('exact major ratios share the signed final rounding boundary', () {
    for (final c in [
      (1, 200, '0.01'),
      (-1, 200, '-0.01'),
      (49, 10000, '0.00'),
      (-49, 10000, '0.00'),
      (1, 3, '0.33'),
      (2, 3, '0.67'),
      (0, 7, '0.00'),
    ]) {
      expect(
        Money.quantizeRatio(
          usd,
          BigInt.from(c.$1),
          BigInt.from(c.$2),
        ).majorText,
        c.$3,
      );
    }
    expect(
      Money.quantizeRatio(
        Currency('JPY', 0),
        BigInt.from(-5),
        BigInt.two,
      ).majorText,
      '-3',
    );
    expect(
      Money.quantizeRatio(
        Currency('KWD', 3),
        BigInt.one,
        BigInt.from(8),
      ).majorText,
      '0.125',
    );
  });
  test('invalid or excessive ratios fail and storage bounds never wrap', () {
    for (final d in [BigInt.zero, -BigInt.one]) {
      expect(
        () => Money.quantizeRatio(usd, BigInt.one, d),
        throwsA(
          isA<MoneyException>().having(
            (e) => e.code,
            'code',
            MoneyError.invalidInput,
          ),
        ),
      );
    }
    for (final pair in [
      (BigInt.one << 4096, BigInt.one),
      (BigInt.one, BigInt.one << 4096),
    ]) {
      expect(
        () => Money.quantizeRatio(usd, pair.$1, pair.$2),
        throwsA(
          isA<MoneyException>().having(
            (e) => e.code,
            'code',
            MoneyError.precision,
          ),
        ),
      );
    }
    expect(
      Money.quantizeRatio(
        usd,
        Money.minMinorUnits,
        BigInt.from(100),
      ).minorUnits,
      Money.minMinorUnits,
    );
    expect(
      Money.quantizeRatio(
        usd,
        Money.maxMinorUnits,
        BigInt.from(100),
      ).minorUnits,
      Money.maxMinorUnits,
    );
    expect(
      () => Money.quantizeRatio(
        usd,
        Money.maxMinorUnits + BigInt.one,
        BigInt.from(100),
      ),
      throwsA(
        isA<MoneyException>().having(
          (e) => e.code,
          'code',
          MoneyError.overflow,
        ),
      ),
    );
  });
}
