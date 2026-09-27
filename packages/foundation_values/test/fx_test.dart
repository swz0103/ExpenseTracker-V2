import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  final usd = Currency('USD', 2);
  final eur = Currency('EUR', 2);
  final jpy = Currency('JPY', 0);
  final gbp = Currency('GBP', 2);
  Matcher error(FxError code) =>
      throwsA(isA<FxException>().having((e) => e.code, 'code', code));
  FxRate rate(String value) => FxRate.parse(usd, eur, value);

  test('decimal rate is exact and canonical without losing small values', () {
    final value = rate('0000.1000');
    expect(value.numerator, BigInt.one);
    expect(value.denominator, BigInt.from(10));
    expect(value, rate('0.1'));
    expect(value.hashCode, rate('0.1').hashCode);
    final tiny = rate('0.${List.filled(125, '0').join()}1');
    expect(tiny.numerator, BigInt.one);
    expect(tiny.denominator, BigInt.from(10).pow(126));
  });
  test('invalid or nonpositive rate is never treated as one or zero', () {
    for (final text in [
      '',
      '0',
      '0.00',
      '-1',
      '+1',
      'NaN',
      'Infinity',
      '1e2',
      ' 1',
      '1 ',
      '1\n',
      '1,000',
      '.1',
      '1.',
      List.filled(129, '1').join(),
    ]) {
      expect(() => rate(text), error(FxError.invalidInput));
    }
    for (final pair in [
      (BigInt.zero, BigInt.one),
      (BigInt.one, BigInt.zero),
      (-BigInt.one, -BigInt.one),
    ]) {
      expect(
        () => FxRate.ratio(usd, eur, pair.$1, pair.$2),
        error(FxError.invalidInput),
      );
    }
  });
  test('conversion keeps ordinary decimal multiplication exact', () {
    expect(
      rate('0.2').convert(Money.parse(usd, '0.10')),
      Money.parse(eur, '0.02'),
    );
    expect(
      rate('1.23456789').convert(Money.parse(usd, '100')),
      Money.parse(eur, '123.46'),
    );
    expect(rate('0.1').convert(Money.parse(usd, '0')), Money.parse(eur, '0'));
  });
  test(
    'base and quote scales apply to major-unit rate, not raw minor units',
    () {
      expect(
        FxRate.parse(jpy, usd, '0.00625').convert(Money.parse(jpy, '160')),
        Money.parse(usd, '1.00'),
      );
      final kwd = Currency('KWD', 3);
      expect(
        FxRate.parse(kwd, jpy, '100').convert(Money.parse(kwd, '1.234')),
        Money.parse(jpy, '123'),
      );
      final tiny = Currency('XXX', 18);
      expect(
        FxRate.parse(
          tiny,
          usd,
          '1000000000000000000',
        ).convert(Money(tiny, BigInt.one)),
        Money.parse(usd, '1'),
      );
    },
  );
  test('final quantization uses the same signed half-away policy as Money', () {
    expect(FxRate.roundingPolicy, Money.roundingPolicy);
    for (final sign in ['', '-']) {
      expect(
        rate('1.005').convert(Money.parse(usd, '${sign}1')).majorText,
        '${sign}1.01',
      );
      expect(
        rate('1.0049').convert(Money.parse(usd, '${sign}1')).majorText,
        '${sign}1.00',
      );
    }
  });
  test('large values and signed minimum stay exact with identity ratio', () {
    for (final units in [
      Money.maxMinorUnits,
      Money.minMinorUnits,
      BigInt.parse('9007199254740993'),
    ]) {
      expect(rate('1').convert(Money(usd, units)), Money(eur, units));
    }
  });
  test('final storage overflow fails instead of wrapping or clipping', () {
    for (final units in [Money.maxMinorUnits, Money.minMinorUnits]) {
      expect(
        () => rate('2').convert(Money(usd, units)),
        throwsA(
          isA<MoneyException>().having(
            (e) => e.code,
            'code',
            MoneyError.overflow,
          ),
        ),
      );
    }
  });
  test('reciprocal of three stays a rational until final conversion', () {
    final inverse = rate('3').inverse();
    expect(inverse.numerator, BigInt.one);
    expect(inverse.denominator, BigInt.from(3));
    expect(inverse.convert(Money.parse(eur, '3')), Money.parse(usd, '1'));
    expect(inverse.inverse(), rate('3'));
  });
  test('cross rate composition never quantizes an intermediate amount', () {
    final third = FxRate.ratio(usd, eur, BigInt.one, BigInt.from(3));
    final composed = third.then(FxRate.parse(eur, gbp, '3'));
    expect(
      composed.convert(Money.parse(usd, '0.01')),
      Money.parse(gbp, '0.01'),
    );
    expect(rate('3').then(rate('3').inverse()), FxRate.parse(usd, usd, '1'));
  });
  test(
    'mismatched currencies, scales and nonidentity same-currency rates fail',
    () {
      expect(
        () => rate('2').convert(Money.parse(jpy, '1')),
        error(FxError.currencyMismatch),
      );
      expect(
        () => rate('2').convert(Money.parse(Currency('USD', 3), '1')),
        error(FxError.currencyMismatch),
      );
      expect(
        () => rate('2').then(FxRate.parse(Currency('EUR', 3), gbp, '1')),
        error(FxError.currencyMismatch),
      );
      expect(
        () => FxRate.parse(usd, usd, '1.01'),
        error(FxError.currencyMismatch),
      );
      expect(
        () => FxRate.parse(usd, Currency('USD', 3), '1'),
        error(FxError.currencyMismatch),
      );
    },
  );
  test('actual principals derive a rate without changing either amount', () {
    final from = Money.parse(usd, '3.00');
    final to = Money.parse(jpy, '1');
    final derived = FxRate.fromAmounts(from, to);
    expect(derived.numerator, BigInt.one);
    expect(derived.denominator, BigInt.from(3));
    expect(derived.convert(from), to);
    expect(derived.inverse().convert(to), from);
    expect(
      () => FxRate.fromAmounts(Money.parse(usd, '0'), to),
      error(FxError.invalidInput),
    );
    expect(
      () => FxRate.fromAmounts(from, Money.parse(jpy, '-1')),
      error(FxError.invalidInput),
    );
  });
  test(
    'ratio bounds reject expansion but cancel factors before composition',
    () {
      final huge = BigInt.from(10).pow(127);
      final first = FxRate.ratio(usd, eur, huge, BigInt.one);
      final next = FxRate.ratio(eur, gbp, BigInt.one, huge);
      expect(first.then(next), FxRate.parse(usd, gbp, '1'));
      expect(
        () => first.then(FxRate.parse(eur, gbp, '10')),
        error(FxError.precision),
      );
      expect(
        () => FxRate.ratio(usd, eur, huge * BigInt.from(10), BigInt.one),
        error(FxError.precision),
      );
    },
  );
  test('versioned JSON preserves ratios above binary floating point range', () {
    final original = FxRate.ratio(
      usd,
      eur,
      BigInt.parse('9007199254740993'),
      BigInt.from(7),
    );
    final json =
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
    expect(json['numerator'], isA<String>());
    expect(FxRate.fromJson(json), original);
    expect(
      FxRate.fromJson(rate('0.1000').toJson()).toJson(),
      rate('0.1').toJson(),
    );
  });
  test(
    'JSON rejects unknown fields, numeric ratios and unsupported formats',
    () {
      final valid = rate('0.5').toJson();
      for (final change in <Map<String, Object?>>[
        {'version': 2},
        {'version': 1.0},
        {'future': 1},
        {'numerator': 1},
        {'denominator': '0'},
        {'numerator': '01'},
        {'numerator': '1.0'},
        {'numerator': List.filled(129, '1').join()},
        {'baseScale': 2.0},
        {'base': 'usd'},
      ]) {
        expect(
          () => FxRate.fromJson({...valid, ...change}),
          error(FxError.invalidInput),
        );
      }
      expect(
        () => FxRate.fromJson({...valid}..remove('quoteScale')),
        error(FxError.invalidInput),
      );
    },
  );
  test('rounded rational is within half a minor unit and sign symmetric', () {
    final base = Currency('XXX', 0);
    final quote = Currency('YYY', 0);
    for (var n = 1; n <= 19; n++) {
      for (var d = 1; d <= 19; d++) {
        final r = FxRate.ratio(base, quote, BigInt.from(n), BigInt.from(d));
        for (var i = 0; i <= 31; i++) {
          final input = BigInt.from(i);
          final result = r.convert(Money(base, input)).minorUnits;
          expect(
            (result * BigInt.from(d) - input * BigInt.from(n)).abs() *
                BigInt.two,
            lessThanOrEqualTo(BigInt.from(d)),
          );
          expect(r.convert(Money(base, -input)).minorUnits, -result);
        }
      }
    }
  });

  FxObservation observation() => FxObservation(
    rate: rate('1.23'),
    source: 'fixture:daily',
    asOf: BusinessDate(2026, 8, 31),
    retrievedAt: UtcInstant.parse('2026-09-27T00:00:00Z'),
  );
  test(
    'older observation requires explicit last-known policy; future is rejected',
    () {
      final value = observation();
      expect(value.rateFor(BusinessDate(2026, 8, 31)), value.rate);
      expect(
        () => value.rateFor(BusinessDate(2026, 9, 25)),
        error(FxError.dateMismatch),
      );
      expect(
        value.rateFor(BusinessDate(2026, 9, 25), allowEarlier: true),
        value.rate,
      );
      expect(
        () => value.rateFor(BusinessDate(2026, 8, 30), allowEarlier: true),
        error(FxError.dateMismatch),
      );
      expect(value.asOf, BusinessDate(2026, 8, 31));
    },
  );
  test(
    'observation round trip keeps actual source date and retrieval instant',
    () {
      final original = observation();
      final restored = FxObservation.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), original.toJson());
      expect(restored.rate, original.rate);
    },
  );
  test(
    'observation rejects unknown data, invalid dates and unbounded source text',
    () {
      final valid = observation().toJson();
      for (final change in <Map<String, Object?>>[
        {'version': 2},
        {'version': 1.0},
        {'future': true},
        {'source': ''},
        {'source': 'bad secret /'},
        {'source': List.filled(97, 'a').join()},
        {'asOf': '2026-02-30'},
        {'asOf': '2026-09-27T00:00:00Z'},
        {'retrievedAt': '2026-09-27'},
        {'rate': '1.23'},
      ]) {
        expect(
          () => FxObservation.fromJson({...valid, ...change}),
          error(FxError.invalidInput),
        );
      }
    },
  );
}
