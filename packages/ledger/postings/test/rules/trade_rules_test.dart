import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/intents.dart';
import 'package:ledger_postings/model/vocabulary.dart';
import 'package:test/test.dart';

import '../support/book.dart';

final m = quantityScale;

BigInt q(int shares) => quantityOfUnits(shares);

Buy buy(String id, int d, int seq, int shares, int gross, int fee) => Buy(
  id: IntentId(id),
  date: day(9, d),
  seq: seq,
  cash: bank,
  code: '2330',
  gross: gross,
  shares: shares,
  fee: fee,
);

Dividend dividend(
  String id,
  int d,
  int seq, {
  int gross = 0,
  int tax = 0,
  int shares = 0,
  bool split = false,
  String code = '2330',
}) => Dividend(
  id: IntentId(id),
  date: day(9, d),
  seq: seq,
  cash: bank,
  code: code,
  gross: gross,
  tax: tax,
  shares: shares,
  split: split,
);

void main() {
  late Book b;
  void ok(LedgerIntent i) =>
      expect(keep(b, i), isA<Written>(), reason: i.id.value);
  AccountSum? held() => b.store.sums()[(stock, homeCurrency)];
  int realised() => -(b.reader
      .bySub(Fixed.realisedGains)
      .where((l) => l.sub == '2330')
      .fold(0, (s, l) => s + l.amount));

  setUp(() {
    b = book();
    ok(buy('b1', 4, 1, 100, 60000, 85));
    ok(buy('b2', 7, 2, 100, 65000, 92));
  });

  test('a buy: its lot cost what it paid, fee and all', () {
    expect(linesOf(b, 'b1'), [
      ('acct:bank', -60085, 'TWD', 20260904), // 60000 + 85
      ('holding:2330', 60085, 'TWD', 20260904),
    ]);
    expect(b.reader.bySub(stock), [
      (sub: 'b1', quantity: q(100), amount: 60085),
      (sub: 'b2', quantity: q(100), amount: 65092),
    ]);
  });

  test('a sale takes the oldest lots first; the gain is by stock', () {
    ok(
      Sell(
        id: const IntentId('s1'),
        date: day(9, 10),
        seq: 3,
        cash: bank,
        code: '2330',
        gross: 105000,
        shares: 150,
        fee: 149,
        tax: 315,
      ),
    );
    // Got 105000 - 149 - 315 = 104536; cost 60085 + 65092 × 50/100
    // = 60085 + 32546 = 92631; gain 104536 - 92631 = 11905.
    expect(b.reader.balance(bank), -125177 + 104536);
    expect(realised(), 11905);
    expect(held(), (amount: 32546, quantity: q(50)));
    // At the average cost: 25 of the 50 left, 32546 × 25/50 = 16273;
    // got 20000 - 28 - 60 = 19912; gain 3639.
    ok(
      Sell(
        id: const IntentId('s2'),
        date: day(9, 12),
        seq: 4,
        cash: bank,
        code: '2330',
        gross: 20000,
        shares: 25,
        fee: 28,
        tax: 60,
        average: true,
      ),
    );
    expect(realised(), 11905 + 3639);
    expect(held(), (amount: 16273, quantity: q(25)));
  });

  test('selling more than is held is refused, naming the stock', () {
    final r = keep(
      b,
      Sell(
        id: const IntentId('s'),
        date: day(9, 10),
        seq: 3,
        cash: bank,
        code: '2330',
        gross: 1,
        shares: 201,
      ),
    ) as RuleRejected;
    expect((r.code, r.detail), ('oversold', '2330'));
  });

  test('an earlier buy changed posts the later sale again', () {
    ok(
      Sell(
        id: const IntentId('s1'),
        date: day(9, 10),
        seq: 3,
        cash: bank,
        code: '2330',
        gross: 105000,
        shares: 150,
        fee: 149,
        tax: 315,
      ),
    );
    // b1 now cost 50000: 50000 + 32546 = 82546; gain 104536 - 82546.
    ok(buy('b1', 4, 1, 100, 49915, 85));
    expect(realised(), 21990);
    final r = keep(b, buy('b1', 4, 1, 40, 1, 0)) as RuleRejected;
    expect((r.intent, r.code), (const IntentId('s1'), 'oversold'));
  });

  test('cash dividends, a stock dividend, a split and a reduction', () {
    ok(dividend('d', 8, 3, gross: 4500, tax: 95));
    // 4500 - 95 = 4405 paid, kept as the stock's dividends.
    expect(linesOf(b, 'd'), [
      ('acct:bank', 4405, 'TWD', 20260908),
      ('income:dividends', -4405, 'TWD', 20260908),
    ]);
    // 10 more for the 200 held: every lot × 210/200, cost kept.
    ok(dividend('stock', 9, 4, shares: 10));
    expect(b.reader.bySub(stock), [
      (sub: 'b1', quantity: q(105), amount: 60085),
      (sub: 'b2', quantity: q(105), amount: 65092),
    ]);
    // A split, 2 for 1.
    ok(dividend('split', 10, 5, shares: 210, split: true));
    expect(held(), (amount: 125177, quantity: q(420)));
    // A reduction: 420 → 210, 5000 back off the cost, in proportion.
    ok(dividend('cut', 11, 6, gross: 5000, shares: -210));
    expect(held(), (amount: 120177, quantity: q(210))); // 125177 - 5000
    expect(realised(), 0);
    expect(b.reader.balance(bank), -125177 + 4405 + 5000);
  });

  test('a reduction of every share leaves on the holding what the '
      'capital did not cover', () {
    // 5000 back on 125177 of cost.
    ok(dividend('wipe', 9, 3, gross: 5000, shares: -200));
    expect(held(), (amount: 120177, quantity: BigInt.zero));
    expect(realised(), 0);
    // More back than the cost: the rest is a gain.
    final c = book();
    b = c;
    ok(buy('x', 4, 1, 10, 1000, 0));
    ok(dividend('wipe', 9, 3, gross: 1500, shares: -10));
    expect(held(), isNull); // nothing held, nothing cost
    expect(realised(), 500); // 1500 - 1000
    final r =
        keep(b, dividend('more', 10, 4, gross: 1, shares: -1)) as RuleRejected;
    expect(r.code, 'oversold');
  });

  test('shares given with nothing held start a lot of their own', () {
    ok(
      Sell(
        id: const IntentId('all'),
        date: day(9, 8),
        seq: 3,
        cash: bank,
        code: '2330',
        gross: 1,
        shares: 200,
      ),
    );
    ok(dividend('free', 9, 4, shares: 7));
    expect(b.reader.bySub(stock), [(sub: 'free', quantity: q(7), amount: 0)]);
  });

  test('a dividend naming no stock is income all the same', () {
    ok(dividend('d', 8, 3, gross: 1000, tax: 20, code: ''));
    expect(b.reader.bySub(Fixed.dividends), [
      (sub: '', quantity: BigInt.zero, amount: -980),
    ]);
    final r =
        keep(b, dividend('s', 8, 4, shares: 1, code: 'none')) as RuleRejected;
    expect((r.code, r.detail), ('noHoldingAccount', 'none'));
    final cash = keep(
      b,
      Dividend(
        id: const IntentId('c'),
        date: day(9, 1),
        seq: 5,
        cash: food,
        code: '',
        gross: 1,
      ),
    ) as RuleRejected;
    expect(cash.code, 'notAMoneyAccount');
  });

  test('a lot of a fraction of a share is kept exactly, as the lot '
      'arithmetic counts it (D87)', () {
    b = book();
    ok(buy('one', 1, 1, 1, 100, 0));
    ok(buy('more', 2, 2, 127, 12700, 0));
    // 1 more for the 128 held: the first lot becomes 129/128 =
    // 1.0078125 shares, the second 127 × 129/128 = 127.9921875: exact at
    // 10^-12 of a share, adding up to the 129 shares held.
    ok(dividend('odd', 3, 3, shares: 1));
    expect(b.reader.bySub(stock), [
      (sub: 'one', quantity: BigInt.from(1007812500000), amount: 100),
      (sub: 'more', quantity: BigInt.from(127992187500000), amount: 12700),
    ]);
    expect(held()!.quantity, q(129));
  });

  test('what a stock held from the start', () {
    b = book();
    ok(
      OpeningPosition(
        id: const IntentId('p'),
        seq: 0,
        code: '2330',
        shares: 1000,
        cost: 120000,
        realised: 50,
        dividends: 30,
      ),
    );
    expect(linesOf(b, 'p'), [
      ('holding:2330', 120000, 'TWD', 10101),
      ('income:realised', -50, 'TWD', 10101),
      ('income:dividends', -30, 'TWD', 10101),
      ('equity:positions', -119920, 'TWD', 10101), // 50 + 30 - 120000
    ]);
    final r = keep(
      b,
      OpeningPosition(
        id: const IntentId('q'),
        seq: 0,
        code: 'none',
        shares: 1,
        cost: 1,
      ),
    ) as RuleRejected;
    expect(r.code, 'noHoldingAccount');
  });

  test('an old trade the holdings leave out moves only money', () {
    ok(
      OutOfHoldings(
        id: const IntentId('o'),
        date: day(9, 9),
        seq: 3,
        cash: bank,
        settlement: 777,
        reason: OutOfHoldingsReason.oversold,
      ),
    );
    expect(linesOf(b, 'o'), [
      ('acct:bank', 777, 'TWD', 20260909),
      ('equity:out-of-holdings', -777, 'TWD', 20260909),
    ]);
    final r = keep(
      b,
      OutOfHoldings(
        id: const IntentId('x'),
        date: day(9, 9),
        seq: 4,
        cash: food,
        settlement: 1,
        reason: OutOfHoldingsReason.noStock,
      ),
    ) as RuleRejected;
    expect(r.code, 'notAMoneyAccount');
    expect(OutOfHoldingsReason.values.length, 2);
  });

  test('a trade of a stock with no holding account is refused', () {
    final r = keep(
      b,
      Buy(
        id: const IntentId('x'),
        date: day(9, 1),
        seq: 9,
        cash: bank,
        code: 'none',
        gross: 1,
        shares: 1,
      ),
    ) as RuleRejected;
    expect((r.code, r.detail), ('noHoldingAccount', 'none'));
    final s = keep(
      b,
      Sell(
        id: const IntentId('y'),
        date: day(9, 1),
        seq: 9,
        cash: bank,
        code: 'none',
        gross: 1,
        shares: 1,
      ),
    ) as RuleRejected;
    expect(s.code, 'noHoldingAccount');
  });
}
