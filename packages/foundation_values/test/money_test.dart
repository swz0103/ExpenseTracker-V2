import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  final usd = Currency('USD', 2);
  Matcher error(MoneyError code) =>
      throwsA(isA<MoneyException>().having((e) => e.code, 'code', code));

  test('VAL-01 exact addition and serialized string', () {
    final result = Money.parse(usd, '0.10') + Money.parse(usd, '0.20');
    expect(result.minorUnits, BigInt.from(30));
    expect(result.majorText, '0.30');
    expect(result.toJson()['minorUnits'], '30');
  });
  test('VAL-02 rejects currency or scale mismatch', () {
    for (final other in [Currency('EUR', 2), Currency('USD', 3)]) {
      expect(
        () => Money.parse(usd, '1') + Money.parse(other, '1'),
        error(MoneyError.currencyMismatch),
      );
    }
  });
  test('VAL-03 allocation preserves positive and negative totals', () {
    for (var amount = -200; amount <= 200; amount++) {
      final value = Money(usd, BigInt.from(amount));
      final shares = value.allocate([BigInt.one, BigInt.one, BigInt.one]);
      expect(
        shares.fold(BigInt.zero, (sum, share) => sum + share.minorUnits),
        value.minorUnits,
      );
      expect(
        shares.every(
          (share) =>
              share.minorUnits.sign == value.minorUnits.sign ||
              share.minorUnits == BigInt.zero,
        ),
        isTrue,
      );
    }
    expect(
      Money.parse(
        usd,
        '1',
      ).allocate(List.filled(3, BigInt.one)).map((m) => m.majorText),
      ['0.33', '0.33', '0.34'],
    );
    expect(
      Money.parse(
        usd,
        '-1',
      ).allocate(List.filled(3, BigInt.one)).map((m) => m.majorText),
      ['-0.33', '-0.33', '-0.34'],
    );
  });
  test('weighted allocation computes products without integer overflow', () {
    final value = Money(usd, Money.maxMinorUnits);
    final shares = value.allocate([Money.maxMinorUnits, Money.maxMinorUnits]);
    expect(shares[0].minorUnits, BigInt.parse('4611686018427387903'));
    expect(shares[1].minorUnits, BigInt.parse('4611686018427387904'));
    expect(shares[0] + shares[1], value);
  });
  test('VAL-04 manual input rejects extra precision', () {
    for (final input in ['0.005', '1.000', '-0.005']) {
      expect(() => Money.parse(usd, input), error(MoneyError.precision));
    }
  });
  test('VAL-04 calculation ties away from zero at final boundary', () {
    for (final entry in {
      '0.005': '0.01',
      '-0.005': '-0.01',
      '0.0049': '0.00',
      '-0.0049': '0.00',
      '1.995': '2.00',
      '-1.995': '-2.00',
    }.entries) {
      final result = Money.quantize(usd, entry.key);
      expect(result.majorText, entry.value);
      expect((-result).minorUnits, -result.minorUnits);
    }
  });
  test('VAL-05 SQLite bounds reject overflow without wrapping', () {
    final max = Money(usd, Money.maxMinorUnits);
    final min = Money(usd, Money.minMinorUnits);
    final unit = Money(usd, BigInt.one);
    expect(() => max + unit, error(MoneyError.overflow));
    expect(() => min - unit, error(MoneyError.overflow));
    expect(() => -min, error(MoneyError.overflow));
    expect(max - max, Money(usd, BigInt.zero));
    expect(() => max - min, error(MoneyError.overflow));
  });
  test('VAL-05 large signed values survive JSON round trip', () {
    for (final amount in [
      Money.minMinorUnits,
      Money.maxMinorUnits,
      BigInt.parse('9007199254740993'),
    ]) {
      final original = Money(usd, amount);
      expect(
        Money.fromJson(
          (jsonDecode(jsonEncode(original.toJson())) as Map)
              .cast<String, Object?>(),
        ),
        original,
      );
      expect(Money.parse(usd, original.majorText), original);
    }
  });
  test('zero and three decimal denominations retain precision', () {
    expect(Money.parse(Currency('JPY', 0), '-12').majorText, '-12');
    expect(
      Money.parse(Currency('KWD', 3), '1.234').minorUnits,
      BigInt.from(1234),
    );
    expect(Money.parse(usd, '-0.00').majorText, '0.00');
  });
  test('reject malformed input and unversioned or numeric JSON', () {
    for (final input in [
      '',
      'NaN',
      '1e2',
      ' 1',
      '1,000',
      '.1',
      '1.',
      '+1',
      '1\n',
    ]) {
      expect(() => Money.parse(usd, input), error(MoneyError.invalidInput));
    }
    final valid = Money.parse(usd, '1').toJson();
    for (final replacement in [
      {'version': 2},
      {'minorUnits': 100},
      {'minorUnits': '0x10'},
      {'scale': 2.5},
    ]) {
      expect(
        () => Money.fromJson({...valid, ...replacement}),
        error(MoneyError.invalidInput),
      );
    }
    expect(() => Currency('usd', 2), error(MoneyError.invalidInput));
    expect(() => Currency('USD', -1), error(MoneyError.invalidInput));
    expect(() => Currency('USD', 19), error(MoneyError.invalidInput));
    expect(
      () => Money.parse(usd, '1').allocate([]),
      error(MoneyError.invalidInput),
    );
    expect(
      () => Money.parse(usd, '1').allocate([BigInt.zero]),
      error(MoneyError.invalidInput),
    );
  });
}
