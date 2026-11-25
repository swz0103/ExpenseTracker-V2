// Share lots: first-in-first-out cost after several buys and partial
// sells, the average-cost alternative, splits, stock dividends, capital
// reductions and overselling. Hand arithmetic is beside each figure.
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'baseline_ledger.dart';

Entry buy(String id, DateTime on, int amount, int shares, int fee) => entryOf(
  id,
  on,
  EntryType.buy,
  amount,
  'bank',
  holding: '2330',
  shares: shares,
  fee: fee,
);

Entry sell(
  String id,
  DateTime on,
  int amount,
  int shares,
  int fee,
  int tax, {
  bool average = false,
}) => entryOf(
  id,
  on,
  EntryType.sell,
  amount,
  'bank',
  holding: '2330',
  shares: shares,
  fee: fee,
  tax: tax,
  average: average,
);

/// Two buys: 1,000 shares costing 100,000 + 85 on Jan 5, and 1,000 costing
/// 120,000 + 102 on Feb 5.
Ledger twoBuys([List<Entry> more = const []]) => ledgerOf(
  today: day(2026, 6, 1),
  accounts: const [Account('bank', '銀行', AccountKind.bank, 1000000)],
  entries: [
    buy('a', day(2026, 1, 5), 100000, 1000, 85),
    buy('b', day(2026, 2, 5), 120000, 1000, 102),
    ...more,
  ],
);

void main() {
  group('first in, first out', () {
    test('two buys make two lots at cost plus fee', () {
      final ledger = twoBuys();
      final lots = ledger.holdings.lotsOf('2330');
      // 100000 + 85 = 100085 and 120000 + 102 = 120102.
      expect(lots.map((l) => (l.shares, l.cost)), [
        (1000, 100085),
        (1000, 120102),
      ]);
      expect(ledger.holding('2330')!.shares, 2000);
      // 100085 + 120102 = 220187.
      expect(ledger.holding('2330')!.cost, 220187);
    });

    test('selling 1,500 takes the whole first lot and half the second', () {
      final ledger = twoBuys();
      // 100085 + 120102 x 500 / 1000 = 100085 + 60051 = 160136.
      expect(ledger.holdings.saleCost('2330', 1500), 160136);
    });

    test('after the sale the rest is the second lot, halved', () {
      final ledger = twoBuys([
        sell('s', day(2026, 3, 5), 195000, 1500, 166, 585),
      ]);
      final h = ledger.holding('2330')!;
      expect(h.shares, 500);
      // 220187 - 160136 = 60051 (= 120102 / 2).
      expect(h.cost, 60051);
      final lots = ledger.holdings.lotsOf('2330');
      expect(lots.map((l) => (l.date, l.shares, l.cost)), [
        (day(2026, 2, 5), 500, 60051),
      ]);
    });

    test('the realised result is proceeds less fee, tax and cost', () {
      final ledger = twoBuys([
        sell('s', day(2026, 3, 5), 195000, 1500, 166, 585),
      ]);
      // 195000 - 166 - 585 - 160136 = 34113.
      expect(ledger.holding('2330')!.realized, 34113);
      expect(ledger.holdings.realizedGain, 34113);
    });

    test('several partial sells keep taking from the oldest lot', () {
      final ledger = twoBuys([
        sell('s1', day(2026, 3, 1), 50000, 400, 42, 150),
        sell('s2', day(2026, 3, 2), 90000, 700, 76, 270),
      ]);
      // s1: 100085 x 400 / 1000 = 40034. Lot A keeps 600 at 60051.
      // s2: 600 from A (60051) + 100 from B (120102 x 100 / 1000 = 12010.2
      // -> 12010) = 72061. Left: 900 shares, cost 120102 - 12010 = 108092.
      final h = ledger.holding('2330')!;
      expect(h.shares, 900);
      expect(h.cost, 108092);
      // Realised: (50000-42-150-40034) + (90000-76-270-72061)
      // = 9774 + 17593 = 27367.
      expect(h.realized, 27367);
    });

    test('the shares held on a day are counted by the trades up to it', () {
      final ledger = twoBuys([
        sell('s', day(2026, 3, 5), 195000, 1500, 166, 585),
      ]);
      int on(int m, int d) => ledger.holdings.sharesOn('2330', day(2026, m, d));
      expect(on(1, 4), 0);
      expect(on(1, 5), 1000);
      expect(on(2, 4), 1000);
      expect(on(2, 5), 2000);
      expect(on(3, 4), 2000);
      expect(on(3, 5), 500);
    });

    test('buying again after selling everything starts a new lot', () {
      final ledger = ledgerOf(
        today: day(2026, 6, 1),
        accounts: const [Account('bank', '銀行', AccountKind.bank, 1000000)],
        entries: [
          buy('a', day(2026, 1, 5), 100000, 1000, 85),
          sell('s', day(2026, 2, 5), 110000, 1000, 93, 330),
          buy('b', day(2026, 3, 5), 90000, 1000, 77),
        ],
      );
      final h = ledger.holding('2330')!;
      // Only the last buy is held: 90000 + 77 = 90077.
      expect((h.shares, h.cost), (1000, 90077));
      // Realised from the first round: 110000 - 93 - 330 - 100085 = 9492.
      expect(h.realized, 9492);
    });
  });

  group('average cost', () {
    test('selling 1,500 costs 3/4 of everything held', () {
      final ledger = twoBuys();
      // 220187 x 1500 / 2000 = 165140.25 -> 165140.
      expect(ledger.holdings.saleCost('2330', 1500, average: true), 165140);
    });

    test('a sale marked average leaves the average cost behind', () {
      final ledger = twoBuys([
        sell('s', day(2026, 3, 5), 195000, 1500, 166, 585, average: true),
      ]);
      final h = ledger.holding('2330')!;
      // 220187 - 165140 = 55047 left on 500 shares.
      expect((h.shares, h.cost), (500, 55047));
      // 195000 - 166 - 585 - 165140 = 29109.
      expect(h.realized, 29109);
    });
  });

  group('splits, stock dividends and capital reductions', () {
    Ledger held(List<Entry> more) => ledgerOf(
      today: day(2026, 9, 1),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 1000000)],
      entries: [buy('a', day(2026, 1, 5), 100000, 1000, 85), ...more],
    );

    test('a 1-for-1 split doubles the shares and keeps the total cost', () {
      final ledger = held([
        entryOf(
          'sp',
          day(2026, 4, 1),
          EntryType.dividend,
          0,
          'bank',
          holding: '2330',
          shares: 1000,
          split: true,
        ),
      ]);
      final h = ledger.holding('2330')!;
      expect(h.shares, 2000);
      // Total cost is still 100000 + 85 = 100085.
      expect(h.cost, 100085);
      // The price per share halves: 100 (100000 / 1000) / 2 = 50.
      expect(h.price, 50.0);
      expect(h.realized, 0);
      expect(h.dividends, 0);
    });

    test('a split is not income and moves no cash', () {
      final ledger = held([
        entryOf(
          'sp',
          day(2026, 4, 1),
          EntryType.dividend,
          0,
          'bank',
          holding: '2330',
          shares: 1000,
          split: true,
        ),
      ]);
      expect(ledger.reportService.income(2026, 4), 0);
      // 1000000 - 100085 = 899915, untouched by the split.
      expect(ledger.balanceService.balance('bank'), 899915);
    });

    test('earlier share counts are scaled to the new shares', () {
      final ledger = held([
        entryOf(
          'sp',
          day(2026, 4, 1),
          EntryType.dividend,
          0,
          'bank',
          holding: '2330',
          shares: 1000,
          split: true,
        ),
      ]);
      // 1000 held on Jan 5 is 2000 of today's shares.
      expect(ledger.holdings.sharesOn('2330', day(2026, 1, 5)), 2000);
      expect(ledger.holdings.sharesOn('2330', day(2026, 4, 1)), 2000);
    });

    test('stock dividend shares add no cost', () {
      final ledger = held([
        entryOf(
          'sd',
          day(2026, 8, 1),
          EntryType.dividend,
          0,
          'bank',
          holding: '2330',
          shares: 100,
        ),
      ]);
      final h = ledger.holding('2330')!;
      expect(h.shares, 1100);
      // Still 100085 spread over more shares.
      expect(h.cost, 100085);
      expect(
        ledger.holdings.lotsOf('2330').fold(0, (s, l) => s + l.cost),
        100085,
      );
      expect(
        ledger.holdings.lotsOf('2330').fold(0, (s, l) => s + l.shares),
        1100,
      );
      // And it is no cash income.
      expect(ledger.reportService.income(2026, 8), 0);
    });

    test('a capital reduction lowers the cost by the cash returned', () {
      final ledger = held([
        entryOf(
          'cut',
          day(2026, 8, 1),
          EntryType.dividend,
          2000,
          'bank',
          holding: '2330',
          shares: -200,
        ),
      ]);
      final h = ledger.holding('2330')!;
      expect(h.shares, 800);
      // 100085 - 2000 returned = 98085.
      expect(h.cost, 98085);
      // Nothing is gained or lost yet.
      expect(h.realized, 0);
    });

    test('a capital reduction pays in cash but is not income', () {
      final ledger = held([
        entryOf(
          'cut',
          day(2026, 8, 1),
          EntryType.dividend,
          2000,
          'bank',
          holding: '2330',
          shares: -200,
        ),
      ]);
      // 1000000 - 100085 + 2000 = 901915.
      expect(ledger.balanceService.balance('bank'), 901915);
      expect(ledger.reportService.income(2026, 8), 0);
      expect(ledger.holding('2330')!.dividends, 0);
    });
  });

  group('overselling is refused', () {
    test('a sale of more than is held throws and changes nothing', () {
      final ledger = twoBuys();
      expect(
        () => ledger.entryCommands.add(
          sell('x', day(2026, 3, 1), 300000, 2001, 255, 900),
        ),
        throwsA(isA<RecordRefused>()),
      );
      expect(ledger.entries.all.map((e) => e.id), ['a', 'b']);
      expect(ledger.holding('2330')!.shares, 2000);
      // The balance is as before: 1000000 - 100085 - 120102 = 779813.
      expect(ledger.balanceService.balance('bank'), 779813);
    });

    test('selling exactly all that is held is allowed', () {
      final ledger = twoBuys();
      ledger.entryCommands.add(
        sell('x', day(2026, 3, 1), 300000, 2000, 255, 900),
      );
      expect(ledger.holding('2330')!.shares, 0);
    });

    test('the validator names the problem before the write', () {
      final ledger = twoBuys();
      final verdict = ledger.entryValidator.validate(
        sell('x', day(2026, 3, 1), 300000, 2001, 255, 900),
      );
      expect(verdict, isA<SaleExceedsHolding>());
    });

    test('a sale dated before the buy is refused as well', () {
      final ledger = twoBuys();
      // Only 1000 shares are held on Jan 10; selling 1500 then is short.
      expect(
        ledger.entryValidator.validate(
          sell('x', day(2026, 1, 10), 150000, 1500, 128, 450),
        ),
        isA<SaleExceedsHolding>(),
      );
    });

    test('a reduction of more shares than held is refused', () {
      final ledger = twoBuys();
      final verdict = ledger.entryValidator.validate(
        entryOf(
          'cut',
          day(2026, 3, 1),
          EntryType.dividend,
          10,
          'bank',
          holding: '2330',
          shares: -2001,
        ),
      );
      expect(verdict, isA<ReductionExceedsHolding>());
    });

    test('a sale with no shares given is refused', () {
      final ledger = twoBuys();
      final verdict = ledger.entryValidator.validate(
        sell('x', day(2026, 3, 1), 1000, 0, 20, 3),
      );
      expect(verdict, isA<MissingShares>());
    });
  });
}
