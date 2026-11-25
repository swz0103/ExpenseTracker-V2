import 'package:core/foundation_values.dart' show BoardSide, BusinessDate;
import 'package:core/fx/dated_figures.dart'
    show DatedFigures, FoundOn, MarketHistory;
import 'package:expense_tracker/src/core/ledger/repositories/market_data_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final friday = DateTime.utc(2026, 10, 2);
  final thursday = DateTime.utc(2026, 10, 1);

  test('nothing fetched yet has no rate, change or quote day', () {
    final market = MarketDataRepository();
    expect(market.quotedOn, isNull);
    expect(market.rates, isEmpty);
    expect(market.rateOf('USD'), isNull);
    expect(market.moveOf('2330'), isNull);
    expect(market.olderQuote('2330'), isNull);
  });

  test('a close older than the newest is told; the newest is not', () {
    final market = MarketDataRepository(
      quotedOn: friday,
      quoteDays: {'2330': friday, '0050': thursday},
    );
    expect(market.olderQuote('2330'), isNull);
    expect(market.olderQuote('0050'), thursday);
    expect(market.olderQuote('9999'), isNull);
  });

  test('without a newest day no close reads as older', () {
    final market = MarketDataRepository(quoteDays: {'0050': thursday});
    expect(market.olderQuote('0050'), isNull);
  });

  test('the maps handed out cannot change the repository', () {
    final market = MarketDataRepository(rates: {'USD': 32.1});
    expect(() => market.rates['JPY'] = 0.2, throwsUnsupportedError);
    expect(() => market.moves['2330'] = 1, throwsUnsupportedError);
    expect(() => market.quoteDays['2330'] = friday, throwsUnsupportedError);
    expect(market.rates, {'USD': 32.1});
  });

  test('the maps given are copied, not kept', () {
    final rates = {'USD': 32.1};
    final market = MarketDataRepository(rates: rates);
    rates['USD'] = 99;
    expect(market.rateOf('USD'), 32.1);
  });

  test('new data takes the place of all that was kept', () {
    final market = MarketDataRepository(
      rates: {'USD': 32.1, 'JPY': 0.21},
      moves: {'2330': 5},
      quotedOn: thursday,
      quoteDays: {'2330': thursday},
    );
    market.replace(
      rates: {'USD': 31.9},
      moves: {'0050': -0.5},
      quotedOn: friday,
      quoteDays: const {},
    );
    expect(market.rates, {'USD': 31.9});
    expect(market.moveOf('2330'), isNull);
    expect(market.moveOf('0050'), -0.5);
    expect(market.quotedOn, friday);
    expect(market.quoteDays, isEmpty);
  });

  test('taking its own maps back keeps them, rather than emptying them', () {
    final market = MarketDataRepository(
      rates: {'USD': 32.1},
      moves: {'2330': 5},
      quotedOn: friday,
      quoteDays: {'2330': thursday},
    );
    market.replaceWith(market);
    expect(market.rates, {'USD': 32.1});
    expect(market.moves, {'2330': 5});
    expect(market.quoteDays, {'2330': thursday});
  });

  test('another repository read anew is taken whole', () {
    final market = MarketDataRepository(rates: {'USD': 32.1});
    market.replaceWith(
      MarketDataRepository(
        rates: {'EUR': 35},
        moves: {'2330': 1},
        quotedOn: friday,
      ),
    );
    expect(market.rates, {'EUR': 35});
    expect(market.moveOf('2330'), 1);
    expect(market.quotedOn, friday);
  });

  group('valueAtHome (D59)', () {
    final market = MarketDataRepository(
      rates: {'USD': 32, 'JPY': 0.2},
      sellRates: {'USD': 32.5},
    );

    test('what is held is valued at the buying rate', () {
      // US$100.00 (10000 cents) x 32 = 3200.
      expect(market.valueAtHome(10000, 'USD'), 3200);
    });

    test('what is owed is valued at the selling rate', () {
      // -US$100.00 x 32.5 = -3250.
      expect(market.valueAtHome(-10000, 'USD'), -3250);
    });

    test('without a selling rate the buying rate stands in', () {
      // -¥1000 x 0.2 = -200.
      expect(market.valueAtHome(-1000, 'JPY'), -200);
    });

    test('NT\$ is itself; a currency without a rate has no value', () {
      expect(market.valueAtHome(-500, 'TWD'), -500);
      expect(market.valueAtHome(100, 'EUR'), isNull);
    });

    test('the selling rates are taken with the rest, and replaced', () {
      expect(market.sellRates, {'USD': 32.5});
      final other = MarketDataRepository()..replaceWith(market);
      expect(other.sellRates, {'USD': 32.5});
      other.replace(
        rates: {'USD': 31},
        moves: const {},
        quotedOn: null,
        quoteDays: const {},
      );
      // A board without selling rates values a debt at the buying rate:
      // -US$100.00 x 31 = -3100.
      expect(other.sellRates, isEmpty);
      expect(other.valueAtHome(-10000, 'USD'), -3100);
    });
  });

  group('D58: rates and closes by day', () {
    BusinessDate d(int m, int day) => BusinessDate(2026, m, day);
    final market = MarketDataRepository(
      rates: {'USD': 32.0, 'JPY': 0.21},
      sellRates: {'USD': 32.5},
      history: MarketHistory(
        buying: DatedFigures({
          'USD': {d(9, 1): 30.0, d(10, 1): 32.0},
        }),
        selling: DatedFigures({
          'USD': {d(9, 1): 30.5},
        }),
        closes: DatedFigures({
          '2330': {d(9, 1): 950.0},
        }),
      ),
    );

    test('a rate by the one rule, on either side', () {
      expect(market.rateOn('USD', DateTime.utc(2026, 9, 15)), (
        figure: 30.0,
        of: d(9, 1),
        found: FoundOn.earlierDay,
      ));
      // Before any day kept: today's, of no known day.
      expect(market.rateOn('USD', DateTime.utc(2026, 8, 1)), (
        figure: 32.0,
        of: null,
        found: FoundOn.today,
      ));
      expect(market.rateOn('JPY', DateTime.utc(2026, 9, 15))?.figure, 0.21);
      expect(
        market
            .rateOn('USD', DateTime.utc(2026, 9, 15), side: BoardSide.selling)
            ?.figure,
        30.5,
      );
      expect(market.rateOn('EUR', DateTime.utc(2026, 9, 15)), isNull);
      expect(market.closeOn('2330', DateTime.utc(2026, 9, 2))?.figure, 950);
      expect(market.closeOn('0050', DateTime.utc(2026, 9, 2)), isNull);
    });

    test('D123: an earlier day more than doubtfulMoveKeptDays older is '
        'not taken; today\'s stands in', () {
      // Selling: 9/1 to 10/1 is 30 days, taken; to 10/2 is 31, not.
      expect(
        market.rateOn(
          'USD',
          DateTime.utc(2026, 10, 1),
          side: BoardSide.selling,
        ),
        (figure: 30.5, of: d(9, 1), found: FoundOn.earlierDay),
      );
      expect(
        market.rateOn(
          'USD',
          DateTime.utc(2026, 10, 2),
          side: BoardSide.selling,
        ),
        (figure: 32.5, of: null, found: FoundOn.todayEarlierTooOld),
      );
      // US$100 owed on 10/2 at today's 32.5: -3,250.
      expect(
        market.valueAtHomeOn(-10000, 'USD', DateTime.utc(2026, 10, 2)),
        -3250,
      );
      // A close: 9/1's on 10/1; on 10/2 the latest kept stands in.
      expect(
        market.closeOn('2330', DateTime.utc(2026, 10, 1))?.found,
        FoundOn.earlierDay,
      );
      expect(market.closeOn('2330', DateTime.utc(2026, 10, 2)), (
        figure: 950.0,
        of: d(9, 1),
        found: FoundOn.todayEarlierTooOld,
      ));
    });

    test('amounts at the rates of a day', () {
      final sep = DateTime.utc(2026, 9, 15);
      // US$100.00 at 30.0: 3,000; owed, at 30.5: -3,050.
      expect(market.toHomeOn(10000, 'USD', sep), 3000);
      expect(market.valueAtHomeOn(10000, 'USD', sep), 3000);
      expect(market.valueAtHomeOn(-10000, 'USD', sep), -3050);
      // JPY has no selling rate: owed at the buying one, ¥1,000 x 0.21.
      expect(market.valueAtHomeOn(-1000, 'JPY', sep), -210);
      // US$100 into yen: 100 x 30.0 / 0.21 = 14,285.7 -> 14,286.
      expect(market.convertOn(10000, 'USD', 'JPY', sep), 14286);
      expect(market.convertOn(3000, 'TWD', 'USD', sep), 10000);
      expect(market.convertOn(10000, 'USD', 'TWD', sep), 3000);
      expect(market.convertOn(10000, 'EUR', 'TWD', sep), isNull);
      expect(market.toHomeOn(500, 'TWD', sep), 500);
      // Today's convert is unchanged: 100 x 32.0 / 0.21 = 15,238.1.
      expect(market.convert(10000, 'USD', 'JPY'), 15238);
    });

    test('what a fetch replaces it with is taken whole', () {
      final m = MarketDataRepository(history: market.history);
      m.replace(
        rates: const {},
        moves: const {},
        quotedOn: null,
        quoteDays: const {},
      );
      expect(m.history.isEmpty, isTrue);
      final other = MarketDataRepository()..replaceWith(market);
      expect(other.closeOn('2330', DateTime.utc(2026, 9, 2))?.figure, 950);
    });
  });
}
