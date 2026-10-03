import 'package:market_adapters/market_adapters.dart';
import 'package:market_data/market_data.dart';
import 'package:test/test.dart';

void main() {
  test('response budgets come from the provider rules', () {
    expect(IoMarketTransport.maximumResponseBytes, marketResponseLimit);
    expect(IoFugleMarketTransport.maximumResponseBytes, fugleResponseLimit);
    expect(
      IoTwelveDataTransport.maximumResponseBytes,
      twelveDataResponseLimit,
    );
    expect(
      IoYahooChartTransport.maximumResponseBytes,
      yahooChartResponseLimit,
    );
  });

  test('Yahoo transport refuses hosts other than the chart endpoint', () {
    expect(
      () => const IoYahooChartTransport().get(
        Uri.parse('https://example.com/v8/finance/chart/AAPL'),
      ),
      throwsArgumentError,
    );
  });
}
