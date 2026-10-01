import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';
import 'package:test/test.dart';

const response = '''{
  "chart": {
    "result": [{
      "meta": {
        "currency": "TWD",
        "symbol": "2330.TW",
        "dataGranularity": "1m"
      },
      "timestamp": [1790730060, 1790730120],
      "indicators": {
        "quote": [{
          "open": [1320, 1322],
          "high": [1325.5, 1326],
          "low": [1315, 1320],
          "close": [1322.5, 1324],
          "volume": [594, 300]
        }]
      }
    }],
    "error": null
  }
}''';

final class FakeYahooTransport implements YahooChartTransport {
  FakeYahooTransport(this.handle);

  final Future<MarketResponse> Function(Uri) handle;
  final requests = <Uri>[];

  @override
  Future<MarketResponse> get(Uri uri) {
    requests.add(uri);
    return handle(uri);
  }
}

InvestmentInstrument instrument({
  String market = 'TWSE',
  String symbol = '2330',
  String currency = 'TWD',
}) => InvestmentInstrument(
  id: PublicId.generate(),
  kind: InstrumentKind.stock,
  marketCode: market,
  symbol: symbol,
  name: symbol,
  tradingCurrency: Currency(currency, 2),
);

void main() {
  test(
    'no-key Yahoo adapter maps Taiwan symbol and keeps latest complete bar',
    () async {
      final transport = FakeYahooTransport(
        (_) async => const MarketResponse(200, response),
      );
      final gateway = YahooChartIntradayGateway(
        transport: transport,
        clock: () =>
            DateTime.fromMillisecondsSinceEpoch(1790730180 * 1000, isUtc: true),
      );

      final result = await gateway.latestBar(
        instrument(),
        interval: IntradayInterval.oneMinute,
      );

      expect(result.state, MarketState.available);
      expect(result.value!.symbol, '2330');
      expect(result.value!.close, '1324');
      expect(result.value!.volume, BigInt.from(300));
      final uri = transport.requests.single;
      expect(uri.host, 'query1.finance.yahoo.com');
      expect(uri.path, '/v8/finance/chart/2330.TW');
      expect(uri.queryParameters['interval'], '1m');
      expect(uri.queryParameters['range'], '1d');
    },
  );

  test('throttle and wrong series remain distinct failures', () async {
    final throttled = YahooChartIntradayGateway(
      transport: FakeYahooTransport((_) async => const MarketResponse(429, '')),
    );
    expect(
      (await throttled.latestBar(
        instrument(),
        interval: IntradayInterval.fiveMinutes,
      )).state,
      MarketState.throttled,
    );

    final wrong = YahooChartIntradayGateway(
      transport: FakeYahooTransport(
        (_) async =>
            MarketResponse(200, response.replaceFirst('2330.TW', '2317.TW')),
      ),
    );
    expect(
      (await wrong.latestBar(
        instrument(),
        interval: IntradayInterval.oneMinute,
      )).state,
      MarketState.failed,
    );
  });

  test(
    'provider supports mapped Taiwan and US markets without authorization',
    () {
      final provider = YahooChartIntradayStockProvider(
        YahooChartIntradayGateway(
          transport: FakeYahooTransport(
            (_) async => const MarketResponse(204, ''),
          ),
        ),
      );

      expect(provider.descriptor.requiresAuthorization, isFalse);
      expect(
        provider.supportsIntraday(instrument(), IntradayInterval.oneMinute),
        isTrue,
      );
      expect(
        provider.supportsIntraday(
          instrument(market: 'XNAS', symbol: 'AAPL', currency: 'USD'),
          IntradayInterval.fiveMinutes,
        ),
        isTrue,
      );
      expect(
        provider.supportsIntraday(
          instrument(market: 'XLON', symbol: 'VOD', currency: 'GBP'),
          IntradayInterval.fiveMinutes,
        ),
        isFalse,
      );
    },
  );
}
