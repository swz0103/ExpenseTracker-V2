import 'dart:math';

import 'package:amount_input/amount_input.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  final usd = Currency('USD', 2), jpy = Currency('JPY', 0);
  List<String> parts(SplitAllocation p) =>
      p.amounts.map((m) => m.majorText).toList();
  SplitAllocation split(
    String amount,
    SplitMethod method,
    List<String> weights,
  ) => proposeSplit(
    Money.parse(usd, amount),
    rows: weights.length,
    method: method,
    weights: weights,
  );
  test(
    'equal distribution uses the largest-remainder policy in minor units',
    () {
      final p = proposeSplit(
        Money.parse(usd, '10'),
        rows: 3,
        method: SplitMethod.equal,
      );
      expect(parts(p), ['3.34', '3.33', '3.33']);
      expect(p.remainderMinorUnits, BigInt.one);
      expect(SplitAllocation.policy, Money.allocationPolicy);
      expect(
        parts(
          proposeSplit(
            Money.parse(jpy, '10'),
            rows: 3,
            method: SplitMethod.equal,
          ),
        ),
        ['4', '3', '3'],
      );
      expect(() => p.amounts.clear(), throwsUnsupportedError);
    },
  );
  test('percentage sum is exact across different decimal scales', () {
    expect(
      parts(split('10', SplitMethod.percentage, ['33.33', '33.33', '33.34'])),
      ['3.33', '3.33', '3.34'],
    );
    expect(parts(split('10', SplitMethod.percentage, ['25.0', '75.00'])), [
      '2.50',
      '7.50',
    ]);
    for (final w in [
      ['33.33', '33.33', '33.33'],
      ['50', '50.000000000000000001'],
    ]) {
      expect(
        () => split('10', SplitMethod.percentage, w),
        throwsA(
          isA<SplitAllocationException>().having(
            (e) => e.code,
            'code',
            SplitAllocationError.percentageTotal,
          ),
        ),
      );
    }
  });
  test('fractional and proportionally scaled ratios yield identical integer amounts', () {
    for (final w in [
      ['1', '2', '3'],
      ['0.1', '0.20', '0.300'],
      ['0.000000000000000001', '0.000000000000000002', '0.000000000000000003'],
    ]) {
      final p = split('10', SplitMethod.ratio, w);
      expect(parts(p), ['1.67', '3.33', '5.00']);
      expect(p.remainderMinorUnits, BigInt.one);
    }
  });
  test('invalid, excessive, zero and negative weights are never silently normalized', () {
    for (final value in [
      '',
      '0',
      '-1',
      '1e2',
      '1+2',
      '1%',
      '1,000',
      '.5',
      '1.',
      'NaN',
      '0.0000000000000000001',
      '1' * 129,
    ]) {
      expect(
        () => split('10', SplitMethod.ratio, [value, '1']),
        throwsA(isA<SplitAllocationException>()),
      );
    }
    expect(parts(split('10', SplitMethod.ratio, [' 1 ', '1'])), [
      '5.00',
      '5.00',
    ]);
  });
  test('invalid total, count, unexpected weights and zero-valued allocations reject', () {
    for (final rows in [0, 1, 17]) {
      expect(
        () => proposeSplit(
          Money.parse(usd, '10'),
          rows: rows,
          method: SplitMethod.equal,
        ),
        throwsA(isA<SplitAllocationException>()),
      );
    }
    for (final amount in ['0', '-1', '0.01']) {
      expect(
        () => proposeSplit(
          Money.parse(usd, amount),
          rows: 2,
          method: SplitMethod.equal,
        ),
        throwsA(isA<SplitAllocationException>()),
      );
    }
    expect(
      () => split('0.02', SplitMethod.ratio, ['1', '100']),
      throwsA(
        isA<SplitAllocationException>().having(
          (e) => e.code,
          'code',
          SplitAllocationError.zeroShare,
        ),
      ),
    );
    expect(
      () => proposeSplit(
        Money.parse(usd, '10'),
        rows: 2,
        method: SplitMethod.equal,
        weights: ['1', '1'],
      ),
      throwsA(isA<SplitAllocationException>()),
    );
    expect(
      () => proposeSplit(
        Money.parse(usd, '10'),
        rows: 2,
        method: SplitMethod.ratio,
        weights: ['1'],
      ),
      throwsA(isA<SplitAllocationException>()),
    );
  });
  test(
    'maximum principal and 128-digit weights never pass through floating point',
    () {
      final total = Money(usd, Money.maxMinorUnits);
      final p = proposeSplit(
        total,
        rows: 16,
        method: SplitMethod.ratio,
        weights: List.filled(16, '9' * 128),
      );
      final q = total.minorUnits ~/ BigInt.from(16);
      expect(p.amounts.take(15).map((m) => m.minorUnits), everyElement(q));
      expect(p.amounts.last.minorUnits, total.minorUnits - q * BigInt.from(15));
      expect(
        p.amounts.fold(BigInt.zero, (a, b) => a + b.minorUnits),
        total.minorUnits,
      );
    },
  );
  test('3000 seeded allocations match an independent integer oracle, including exact tail', () {
    final random = Random(17016);
    for (var sample = 0; sample < 3000; sample++) {
      final count = 2 + random.nextInt(15);
      final weights = List.generate(count, (_) => 1 + random.nextInt(1000));
      final total = 100000 + random.nextInt(900000000);
      final divisor = weights.fold<int>(0, (a, b) => a + b);
      final expected = weights.map((w) => total * w ~/ divisor).toList();
      final remainder = total - expected.fold<int>(0, (a, b) => a + b);
      int fraction(int i) => total * weights[i] % divisor;
      final order = List.generate(count, (i) => i)
        ..sort((a, b) {
          final byFraction = fraction(b).compareTo(fraction(a));
          return byFraction != 0 ? byFraction : a.compareTo(b);
        });
      for (final index in order.take(remainder)) {
        expected[index] += 1;
      }
      final proposal = proposeSplit(
        Money(usd, BigInt.from(total)),
        rows: count,
        method: SplitMethod.ratio,
        weights: weights.map((w) => '$w').toList(),
      );
      expect(
        proposal.amounts.map((m) => m.minorUnits.toInt()),
        expected,
        reason: 'sample $sample',
      );
      expect(proposal.remainderMinorUnits.toInt(), remainder);
    }
  });
}
