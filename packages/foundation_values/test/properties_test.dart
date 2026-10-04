import 'dart:math';

import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

/// Properties checked on many seeded random inputs (code audit P3); a
/// failure prints the seed and case so it can be replayed.
void main() {
  final twd = Currency.of('TWD');
  final usd = Currency.of('USD');
  final jpy = Currency.of('JPY');
  final eur = Currency.of('EUR');

  BigInt big(Random random, int digits) {
    var value = BigInt.zero;
    for (var i = 0; i < digits; i++) {
      value = value * BigInt.from(10) + BigInt.from(random.nextInt(10));
    }
    return value;
  }

  test('allocation keeps the total and each share within one unit', () {
    final random = Random(20261004);
    for (var round = 0; round < 2000; round++) {
      final sign = random.nextBool() ? BigInt.one : -BigInt.one;
      final total = Money(usd, sign * big(random, 1 + random.nextInt(14)));
      final count = 1 + random.nextInt(20);
      final weights = [
        for (var i = 0; i < count; i++) BigInt.from(1 + random.nextInt(1000)),
      ];
      final shares = total.allocate(weights);
      final sum = shares.fold(BigInt.zero, (a, b) => a + b.minorUnits);
      final weight = weights.fold(BigInt.zero, (a, b) => a + b);
      final reason = 'round $round: ${total.minorUnits} by $weights';
      expect(sum, total.minorUnits, reason: reason);
      for (final (i, share) in shares.indexed) {
        // |share × W − total × w| < W means within one minor unit.
        final gap = share.minorUnits * weight - total.minorUnits * weights[i];
        expect(gap.abs() < weight, isTrue, reason: reason);
        expect(share.minorUnits.isNegative && sign > BigInt.zero, isFalse);
      }
    }
  });

  test('rates compose associatively and invert exactly', () {
    final random = Random(20261005);
    FxRate rate(Currency base, Currency quote) => FxRate.ratio(
      base,
      quote,
      BigInt.from(1 + random.nextInt(1 << 30)),
      BigInt.from(1 + random.nextInt(1 << 30)),
    );
    for (var round = 0; round < 1000; round++) {
      final a = rate(twd, usd);
      final b = rate(usd, jpy);
      final c = rate(jpy, twd);
      final left = a.then(b).then(c);
      final right = a.then(b.then(c));
      expect(
        (left.numerator, left.denominator),
        (right.numerator, right.denominator),
        reason: 'round $round',
      );
      final there = a.then(a.inverse());
      expect((there.numerator, there.denominator), (BigInt.one, BigInt.one));
    }
  });

  test('a conversion and its inverse return within rounding', () {
    final random = Random(20261006);
    for (var round = 0; round < 1000; round++) {
      final rate = FxRate.ratio(
        eur,
        usd,
        BigInt.from(1 + random.nextInt(1 << 24)),
        BigInt.from(1 + random.nextInt(1 << 20)),
      );
      final amount = Money(eur, big(random, 1 + random.nextInt(10)));
      final back = rate.inverse().convert(rate.convert(amount));
      // Half a cent of rounding on the way there, scaled back by the rate,
      // plus half a cent on the way back.
      final bound = rate.denominator ~/ rate.numerator + BigInt.from(2);
      final gap = (back.minorUnits - amount.minorUnits).abs();
      final ratio = '${rate.numerator}/${rate.denominator}';
      final reason = 'round $round: ${amount.minorUnits} at $ratio';
      expect(gap <= bound, isTrue, reason: reason);
    }
  });
}
