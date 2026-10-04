import 'package:market_adapters/market_adapters.dart';
import 'package:test/test.dart';

/// Every check here runs before any connection is opened, so these tests
/// need no network.
void main() {
  test('each transport refuses hosts and paths it was not built for', () {
    final cases = <String, Future<Object?> Function()>{
      'Yahoo on another host': () => const IoYahooChartTransport().get(
        Uri.parse('https://example.com/v8/finance/chart/AAPL'),
      ),
      'Yahoo over http': () => const IoYahooChartTransport().get(
        Uri.parse('http://query1.finance.yahoo.com/v8/finance/chart/AAPL'),
      ),
      'Fugle outside market data': () => const IoFugleMarketTransport().get(
        Uri.parse('https://api.fugle.tw/other/2330'),
        apiKey: 'key',
      ),
      'Twelve Data other path': () => const IoTwelveDataTransport().get(
        Uri.parse('https://api.twelvedata.com/quote'),
        apiKey: 'key',
      ),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(value, throwsArgumentError, reason: key);
    }
  });

  test('API keys that could break a header are refused', () {
    final fugle = Uri.parse(
      'https://api.fugle.tw/marketdata/v1.0/stock/intraday/quote/2330',
    );
    final twelve = Uri.parse('https://api.twelvedata.com/time_series');
    for (final key in ['', 'a b', 'line\nbreak', '金鑰', 'x' * 513]) {
      expect(
        () => const IoFugleMarketTransport().get(fugle, apiKey: key),
        throwsArgumentError,
        reason: 'Fugle ${key.length}',
      );
      expect(
        () => const IoTwelveDataTransport().get(twelve, apiKey: key),
        throwsArgumentError,
        reason: 'Twelve Data ${key.length}',
      );
    }
  });
}
