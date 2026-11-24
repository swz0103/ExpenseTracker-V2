import 'package:kernel/kernel.dart';
import 'package:ledger_postings/calc/lots.dart';
import 'package:ledger_postings/model/vocabulary.dart';
import 'package:test/test.dart';

import '../support/book.dart';

final share = BigInt.from(10).pow(12);

Posting p(String sub, int quantity, int amount, int seq) => Posting(
  intent: IntentId('i$seq'),
  line: 0,
  account: stock,
  amount: amount,
  currency: const CurrencyCode('TWD'),
  date: day(1, seq),
  seq: seq,
  quantity: quantity,
  sub: sub,
);

void main() {
  test('lots are the sums of the postings naming them, oldest first', () {
    final lots = lotsOf([
      p('a', 10 * quantityScale, 1000, 1),
      p('b', 5 * quantityScale, 600, 2),
      p('a', -10 * quantityScale, -1000, 3),
      p('c', 2500000, 50, 4), // 2.5 shares
    ]);
    expect(lots, [
      (sub: 'b', units: share * BigInt.from(5), cost: 600),
      (sub: 'c', units: BigInt.from(2500000000000), cost: 50),
    ]);
    // 7.5 shares held: 8 when rounded half up.
    expect(sharesHeld(lots), 8);
    expect(quantityOfShares(3), 3000000);
  });

  test('a sale by the app\'s own arithmetic; more than held is none', () {
    final lots = [
      (sub: 'a', units: share * BigInt.from(10), cost: 1000),
      (sub: 'b', units: share * BigInt.from(10), cost: 1500),
    ];
    final fifo = sale(lots, 15, average: false)!;
    // All of a (1000) and half of b (750).
    expect(fifo.cost, 1750);
    expect(fifo.changes, [
      (sub: 'a', units: -share * BigInt.from(10), cost: -1000),
      (sub: 'b', units: -share * BigInt.from(5), cost: -750),
    ]);
    // At the average: 2500 × 15/20 = 1875.
    expect(sale(lots, 15, average: true)!.cost, 1875);
    expect(sale(lots, 21, average: false), isNull);
  });

  test('re-ratioed lots, pooled into the newest when they cannot be', () {
    final lots = [
      (sub: 'a', units: share * BigInt.from(1), cost: 100),
      (sub: 'b', units: share * BigInt.from(2), cost: 200),
    ];
    final double = reratio(
      lots,
      newShares: 6,
      oldShares: 3,
      currency: homeCurrency,
    );
    expect(double.changes, [
      (sub: 'a', units: share, cost: 0),
      (sub: 'b', units: share * BigInt.from(2), cost: 0),
    ]);
    // 7 for 3 held as whole shares: lots of 7/3 and 14/3 shares cannot
    // be counted exactly, so they are pooled into b first.
    final pooled = reratio(
      lots,
      newShares: 7,
      oldShares: 3,
      currency: homeCurrency,
    );
    expect(pooled.changes, [
      (sub: 'a', units: -share, cost: -100),
      (sub: 'b', units: share * BigInt.from(5), cost: 100),
    ]);
    expect((pooled.dropped, pooled.lowered), (0, 0));
  });

  test('changes as lines; a lot finer than a millionth rounded and '
      'counted, one too large refused', () {
    final lines = lotLines(stock, [
      (sub: 'a', units: share, cost: 5),
    ], homeCurrency) as Lines;
    expect(
      [for (final l in lines.lines) (l.quantity, l.amount, l.sub)],
      [(1000000, 5, 'a')],
    );
    expect(lines.rounded, 0);
    // 1.5 millionths of a share: to even, 2.
    final fine = lotLines(stock, [
      (sub: 'a', units: BigInt.from(1500000), cost: 0),
    ], homeCurrency) as Lines;
    expect((fine.lines.single.quantity, fine.rounded), (2, 1));
    final huge = lotLines(stock, [
      (sub: 'a', units: share * BigInt.from(10).pow(10), cost: 0),
    ], homeCurrency) as Refused;
    expect(huge.code, 'quantity.tooLarge');
  });
}
