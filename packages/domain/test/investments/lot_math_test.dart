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

  group('edges review 11 found untested', () {
    test('a whole share is 10^12 units', () {
      expect(unitsPerShare, BigInt.parse('1000000000000'));
    });

    test('by oldest lots, a lot not sold from keeps all its cost', () {
      final sale = sellFromLots(
        [lot(10, 100), lot(10, 100)],
        shares(3),
        InvestmentCostMethod.fifo,
      );
      // 100 x 3/10 = 30 from the first; nothing from the second.
      expect(sale.saleCosts, [BigInt.from(30), BigInt.zero]);
      expect(sale.remaining, [
        LotPosition(shares(7), BigInt.from(70)),
        LotPosition(shares(10), BigInt.from(100)),
      ]);
    });

    test('selling nothing changes nothing', () {
      final sale = sellFromLots(
        [lot(10, 100)],
        BigInt.zero,
        InvestmentCostMethod.fifo,
      );
      expect(sale.cost, BigInt.zero);
      expect(sale.remaining, [lot(10, 100)]);
    });

    test('by average cost, what stays is spread by the units left', () {
      final sale = sellFromLots(
        [lot(10, 100), lot(10, 100), lot(10, 100)],
        shares(5),
        InvestmentCostMethod.averageCost,
      );
      // 300 x 5/30 = 50 sold; the 250 kept over 5, 10 and 10 shares:
      // 250 x 5/25 = 50, 250 x 10/25 = 100, the last the rest 100.
      expect(sale.saleCosts, [BigInt.from(50), BigInt.zero, BigInt.zero]);
      expect(sale.remaining, [
        LotPosition(shares(5), BigInt.from(50)),
        LotPosition(shares(10), BigInt.from(100)),
        LotPosition(shares(10), BigInt.from(100)),
      ]);
    });

    test('by average cost, shares round down and the last lot sold from '
        'takes the rest', () {
      final sale = sellFromLots(
        [lot(3, 10), lot(3, 10), lot(3, 10)],
        shares(4),
        InvestmentCostMethod.averageCost,
      );
      // 30 x 4/9 = 13.3 -> 13 sold, from 3 and 1 shares: 13 x 3/4 = 9.75
      // -> 9, the last sold from the rest 4. Kept 17 over 2 and 3 shares:
      // 17 x 2/5 = 6.8 -> 6, the last 11.
      expect(sale.saleCosts, [BigInt.from(9), BigInt.from(4), BigInt.zero]);
      expect(sale.remaining, [
        LotPosition(BigInt.zero, BigInt.zero),
        LotPosition(shares(2), BigInt.from(6)),
        LotPosition(shares(3), BigInt.from(11)),
      ]);
    });

    test('a fraction of a share left over is dropped from the one lot, '
        'with its cost', () {
      // 3 shares for 2: 3 -> 4.5; the half share goes, with
      // 1,000 x 0.5/4.5 = 111.1 -> 111 of the cost.
      final after = reratioLots(
        [lot(3, 1000)],
        newShares: 3,
        oldShares: 2,
        currency: twd,
        wholeSharesOnly: true,
      )!;
      expect(after.droppedUnits, unitsPerShare ~/ BigInt.two);
      expect(after.droppedCost, BigInt.from(111));
      expect(after.lots, [LotPosition(shares(4), BigInt.from(889))]);
    });

    test('a dropped fraction skips an empty newest lot and its cost rounds '
        'half up', () {
      final quarter = unitsPerShare ~/ BigInt.from(4);
      // 1.25 shares in all: the quarter goes from the one-share lot (the
      // empty lot after it skipped), with 2 x 0.25/1 = 0.5 -> 1 of cost.
      final after = reratioLots(
        [
          LotPosition(quarter, BigInt.from(9)),
          lot(1, 2),
          LotPosition(BigInt.zero, BigInt.zero),
        ],
        newShares: 1,
        oldShares: 1,
        currency: twd,
        wholeSharesOnly: true,
      )!;
      expect(after.droppedCost, BigInt.one);
      expect(after.lots, [
        LotPosition(quarter, BigInt.from(9)),
        LotPosition(unitsPerShare - quarter, BigInt.one),
        LotPosition(BigInt.zero, BigInt.zero),
      ]);
    });

    test('capital returned comes off the lots that have a cost', () {
      final after = reratioLots(
        [lot(1, 0), lot(1, 100)],
        newShares: 1,
        oldShares: 1,
        currency: twd,
        capitalReturned: BigInt.from(10),
      )!;
      expect(after.basisLowered, BigInt.from(10));
      expect(after.lots, [lot(1, 0), lot(1, 90)]);
      // Nothing returned on lots of no cost: nothing to share out.
      final none = reratioLots(
        [lot(1, 0)],
        newShares: 2,
        oldShares: 1,
        currency: twd,
      )!;
      expect(none.lots, [lot(2, 0)]);
      expect(none.basisLowered, BigInt.zero);
    });
  });
}
