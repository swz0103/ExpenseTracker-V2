import 'dart:math';

import 'package:expense_tracker/src/core/ledger/repositories/market_data_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/money/price.dart' show timesPrice;

/// [n] / [d] rounded half away from zero, on whole numbers only: the
/// answer a sum of decimals should give.
int exact(int n, int d) {
  final q = n.abs() ~/ d;
  final up = 2 * (n.abs() % d) >= d ? q + 1 : q;
  return n < 0 ? -up : up;
}

void main() {
  test('a value on a half rounds as written, not as a double holds it', () {
    // 2,730 × 662.05 is 1,807,396.5; as doubles, 1,807,396.4999999998.
    expect((2730 * 662.05).round(), 1807396);
    expect(timesPrice(2730, 662.05), 1807397);
    expect(timesPrice(-2730, 662.05), -1807397);
    expect(timesPrice(3, 0.15), 0);
    expect(timesPrice(50, 12.01), 601);
  });

  test('any count at any two-decimal price is exact', () {
    final r = Random(3);
    for (var i = 0; i < 200000; i++) {
      final count = r.nextInt(2000000) - 1000000;
      final cents = r.nextInt(500000);
      expect(
        timesPrice(count, cents / 100),
        exact(count * cents, 100),
        reason: '$count × ${cents / 100}',
      );
    }
  });

  test('a foreign amount in NT\$ is exact at any four-decimal rate', () {
    // 92,200.00 at 32.1125 is 2,960,772.5; as doubles, 2,960,772.4999...
    final market = MarketDataRepository(rates: {'USD': 32.1125});
    expect(market.toHome(9220000, 'USD'), 2960773);
    final r = Random(4);
    for (var i = 0; i < 200000; i++) {
      final minor = r.nextInt(2000000000) - 1000000000;
      final rate = 1 + r.nextInt(500000);
      final m = MarketDataRepository(rates: {'USD': rate / 10000});
      expect(
        m.toHome(minor, 'USD'),
        exact(minor * rate, 100 * 10000),
        reason: '$minor at ${rate / 10000}',
      );
    }
  });

  test('converting between two foreign currencies goes through NT\$', () {
    final market = MarketDataRepository(rates: {'USD': 32, 'JPY': 0.2});
    // 10.00 USD is 320 NT$, which is 1,600 yen.
    expect(market.convert(1000, 'USD', 'JPY'), 1600);
    // 1,600 yen back is 10.00 USD.
    expect(market.convert(1600, 'JPY', 'USD'), 1000);
    expect(market.convert(320, 'TWD', 'USD'), 1000);
    expect(market.convert(1000, 'USD', 'TWD'), 320);
    expect(market.convert(1000, 'USD', 'EUR'), isNull);
  });
}
