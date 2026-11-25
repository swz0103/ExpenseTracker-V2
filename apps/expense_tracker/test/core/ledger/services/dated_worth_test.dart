import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:core/fx/dated_figures.dart' show DatedFigures, MarketHistory;
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/services/dated_worth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kernel/kernel.dart';

import '../journal/posted_book.dart';

/// D58 (replacing D105/D109's today's price and split): a past day's net
/// worth counts foreign money at that day's rates and shares at that
/// day's close in that day's shares, each else the nearest earlier day's;
/// a day before any kept, or at the latest close, as the holdings show
/// it today. The journal values it the same.
void main() {
  BusinessDate d(int m, int day) => BusinessDate(2026, m, day);
  DateTime on(int m, int day) => DateTime.utc(2026, m, day);

  // A fixture book with rates and closes on scattered days.
  Ledger fixture() => Ledger(
    today: on(10, 31),
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 1000000),
      // US$1,000.00 held, US$100.00 owed on a card.
      Account('usd', '美元', AccountKind.bank, 100000, currency: 'USD'),
      Account('ucard', '美元卡', AccountKind.card, -10000, currency: 'USD'),
    ],
    categories: const [],
    entries: [
      Entry(
        id: 'buy',
        date: on(8, 3),
        type: EntryType.buy,
        amount: 900000,
        account: 'bank',
        category: '',
        holding: '2330',
        shares: 1000,
      ),
      // 1-for-1: 1,000 shares become 2,000.
      Entry(
        id: 'split',
        date: on(9, 15),
        type: EntryType.dividend,
        amount: 0,
        account: 'bank',
        category: '',
        holding: '2330',
        shares: 1000,
        split: true,
      ),
    ],
    holdings: const [
      Holding('2330', '台積電', shares: 0, price: 1000, cost: 0, change: 0),
    ],
    budgets: const [],
    recurring: const [],
    rates: const {'USD': 32.0},
    sellRates: const {'USD': 32.5},
    quoteDays: {'2330': on(10, 30)},
    history: MarketHistory(
      buying: DatedFigures({
        'USD': {d(8, 3): 31.0, d(9, 14): 30.5, d(10, 9): 32.0},
      }),
      selling: DatedFigures({
        'USD': {d(8, 3): 31.5, d(10, 9): 32.5},
      }),
      closes: DatedFigures({
        '2330': {d(8, 5): 950.0, d(9, 1): 960.0, d(10, 30): 1000.0},
      }),
    ),
  );

  test('each past day at its own rates and closes, else the nearest '
      'earlier', () {
    final l = fixture();
    // The split halves the price the holdings value at: 1,000 / 2 = 500.
    expect(l.holding('2330')!.price, 500);
    // Bank: 1,000,000 - 900,000 = 100,000 from 8/3 on.
    //
    // 8/4: no close kept on or before it: today's price in today's
    // shares, 1,000 x 2 = 2,000 x 500 = 1,000,000. US$ at 8/3's board:
    // 1,000 x 31.0 = 31,000 held, 100 x 31.5 = 3,150 owed.
    expect(l.balanceService.netWorth(on(8, 4)).invested, 1000000);
    expect(
      l.balanceService.netWorthAt(on(8, 4)),
      100000 + 1000000 + 31000 - 3150,
    );
    // 8/20: 8/5's close, 1,000 shares then: 950,000.
    expect(l.balanceService.netWorth(on(8, 20)).invested, 950000);
    expect(
      l.balanceService.netWorthAt(on(8, 20)),
      100000 + 950000 + 31000 - 3150,
    );
    // 9/20: 9/1's close; the 2,000 held after the split are 1,000 of
    // 9/1's shares: 1,000 x 960 = 960,000. US$ at 9/14's buying rate,
    // 1,000 x 30.5 = 30,500, and 8/3's selling rate.
    expect(l.balanceService.netWorth(on(9, 20)).invested, 960000);
    expect(
      l.balanceService.netWorthAt(on(9, 20)),
      100000 + 960000 + 30500 - 3150,
    );
    // 10/31: the latest close: as the holdings show it today,
    // 2,000 x 500 = 1,000,000; US$ 1,000 x 32 = 32,000, 100 x 32.5 = 3,250.
    expect(l.balanceService.netWorth(on(10, 31)).invested, 1000000);
    expect(
      l.balanceService.netWorthAt(on(10, 31)),
      100000 + 1000000 + 32000 - 3250,
    );
  });

  test('the rule itself: null where today\'s price values the shares', () {
    final l = fixture();
    int? worth(DateTime day, int counted) => datedWorth(
      holdings: l.holdings,
      market: l.marketData,
      code: '2330',
      day: day,
      counted: counted,
    );
    expect(worth(on(8, 4), 1000), isNull);
    expect(worth(on(8, 5), 1000), 950000);
    expect(worth(on(9, 20), 2000), 960000);
    expect(worth(on(10, 30), 2000), isNull);
    // A stock with no close kept at all.
    expect(
      datedWorth(
        holdings: l.holdings,
        market: l.marketData,
        code: '0050',
        day: on(9, 1),
        counted: 10,
      ),
      isNull,
    );
  });

  test('the journal values each day the same', () async {
    final l = fixture();
    final b = await post(l);
    for (final day in [on(8, 4), on(8, 20), on(9, 20), on(10, 31)]) {
      expect(
        b.reader.netWorth(Day.of(BusinessDate.of(day))).net,
        l.balanceService.netWorthAt(day),
        reason: '$day',
      );
    }
  });
}
