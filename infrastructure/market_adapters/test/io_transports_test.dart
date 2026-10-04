import 'package:market_adapters/market_adapters.dart';
import 'package:test/test.dart';

/// The checks run before any connection opens, so no network is needed.
void main() {
  test('only HTTPS to the three market data hosts', () {
    for (final uri in [
      'https://example.com/v1/exchangeReport/STOCK_DAY_ALL',
      'http://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL',
      'https://rate.bot.com.tw.example.com/xrt/flcsv/0/day',
    ]) {
      expect(
        () => const IoMarketTransport().get(Uri.parse(uri)),
        throwsArgumentError,
        reason: uri,
      );
    }
    expect(IoMarketTransport.hosts, {
      'openapi.twse.com.tw',
      'www.tpex.org.tw',
      'rate.bot.com.tw',
    });
  });
}
