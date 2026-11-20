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
}
