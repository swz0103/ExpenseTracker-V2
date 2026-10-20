import 'package:core/foundation_values.dart';
import 'package:domain/investments.dart';
import 'package:test/test.dart';

void main() {
  final twd = Currency.of('TWD');
  LotPosition lot(int shares, int cost) =>
      LotPosition(BigInt.from(shares) * unitsPerShare, BigInt.from(cost));
  BigInt shares(int n) => BigInt.from(n) * unitsPerShare;

  test('oldest lots first, a partial lot giving up cost rounded down', () {
    final sale = sellFromLots(
      [lot(3, 100), lot(3, 200)],
      shares(4),
      InvestmentCostMethod.fifo,
    );
    // 100 + 200 * 1/3 = 166.67, rounded down.
    expect(sale.cost, BigInt.from(166));
    expect(sale.remaining, [
      LotPosition(BigInt.zero, BigInt.zero),
      LotPosition(shares(2), BigInt.from(134)),
    ]);
  });

  test('average cost is rounded once and spread over what stays', () {
    final sale = sellFromLots(
      [lot(3, 100), lot(3, 201)],
      shares(4),
      InvestmentCostMethod.averageCost,
    );
    // 301 * 4/6 = 200.67, rounded down.
    expect(sale.cost, BigInt.from(200));
    expect(sale.remaining.last, LotPosition(shares(2), BigInt.from(101)));
  });

  test('a final sale takes every unit of cost', () {
    for (final method in InvestmentCostMethod.values) {
      final sale = sellFromLots([lot(3, 101), lot(7, 202)], shares(10), method);
      expect(sale.cost, BigInt.from(303));
    }
  });

  test('selling more than held is refused', () {
    expect(
      () => sellFromLots([lot(1, 1)], shares(2), InvestmentCostMethod.fifo),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a stock dividend grows each lot and keeps its cost', () {
    final after = reratioLots(
      [lot(1000, 500000), lot(1000, 600000)],
      newShares: 2100,
      oldShares: 2000,
      currency: twd,
      wholeSharesOnly: true,
    )!;
    expect(after.lots, [lot(1050, 500000), lot(1050, 600000)]);
    expect(after.droppedUnits, BigInt.zero);
  });

  test('a reduction drops the fraction from the newest lot', () {
    final after = reratioLots(
      [lot(10, 1000), lot(5, 500)],
      newShares: 6,
      oldShares: 10,
      currency: twd,
      wholeSharesOnly: true,
      capitalReturned: BigInt.from(600),
    )!;
    // 6 + 3 = 9 shares, none dropped; 600 off 1500 by cost.
    expect(after.lots, [lot(6, 600), lot(3, 300)]);
    expect(after.basisLowered, BigInt.from(600));
  });

  test('returned capital stops at the cost', () {
    final after = reratioLots(
      [lot(10, 100)],
      newShares: 5,
      oldShares: 10,
      currency: twd,
      capitalReturned: BigInt.from(150),
    )!;
    expect(after.lots, [lot(5, 0)]);
    expect(after.basisLowered, BigInt.from(100));
  });
}
