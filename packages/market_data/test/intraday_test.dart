import 'dart:async';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';
import 'package:test/test.dart';

const oneMinuteResponse = '''{
  "date":"2026-09-30",
  "type":"EQUITY",
  "exchange":"TWSE",
  "market":"TSE",
  "symbol":"2330",
  "timeframe":"1",
  "data":[{
    "date":"2026-09-30T09:01:00.000+08:00",
    "open":1320,
    "high":1325.5,
    "low":1315,
    "close":1322.5,
    "volume":594,
    "average":1321.25
  }],
  "sort":"desc"
}''';

final class FakeFugleTransport implements FugleMarketTransport {
  FakeFugleTransport(this.handle);

  final Future<MarketResponse> Function(Uri, String) handle;
  final requests = <(Uri, String)>[];

  @override
  Future<MarketResponse> get(Uri uri, {required String apiKey}) {
    requests.add((uri, apiKey));
    return handle(uri, apiKey);
  }
}

InvestmentInstrument twStock({
  String market = 'TWSE',
  String symbol = '2330',
}) => InvestmentInstrument(
  id: PublicId.generate(),
  kind: InstrumentKind.stock,
  marketCode: market,
  symbol: symbol,
  name: symbol,
  tradingCurrency: Currency('TWD', 2),
);

void main() {
  test(
    'Fugle one-minute bar preserves price, time, volume and API key',
    () async {
      final transport = FakeFugleTransport(
        (_, _) async => const MarketResponse(200, oneMinuteResponse),
      );
      final gateway = FugleIntradayGateway(
        apiKeySource: () async => 'secret-key',
        transport: transport,
        clock: () => DateTime.utc(2026, 9, 30, 1, 2),
      );
      final result = await gateway.latestBar(
        twStock(),
        interval: IntradayInterval.oneMinute,
      );
      expect(result.state, MarketState.available);
      expect(result.value!.close, '1322.5');
      expect(result.value!.high, '1325.5');
      expect(result.value!.volume, BigInt.from(594));
      expect(result.value!.startsAt.value, DateTime.utc(2026, 9, 30, 1, 1));
      expect(result.value!.fetchedAt.value, DateTime.utc(2026, 9, 30, 1, 2));
      final request = transport.requests.single;
      expect(request.$1.host, 'api.fugle.tw');
      expect(request.$1.path, endsWith('/2330'));
      expect(request.$1.queryParameters, {'timeframe': '1', 'sort': 'desc'});
      expect(request.$2, 'secret-key');
    },
  );

  test('five-minute route marks an older real observation stale', () async {
    final body = oneMinuteResponse
        .replaceAll('"timeframe":"1"', '"timeframe":"5"')
        .replaceAll('09:01:00', '09:05:00');
    final gateway = FugleIntradayGateway(
      apiKeySource: () async => 'key',
      transport: FakeFugleTransport((_, _) async => MarketResponse(200, body)),
      clock: () => DateTime.utc(2026, 9, 30, 1, 12),
    );
    final result = await gateway.latestBar(
      twStock(),
      interval: IntradayInterval.fiveMinutes,
    );
    expect(result.state, MarketState.stale);
    expect(result.value!.startsAt.value, DateTime.utc(2026, 9, 30, 1, 5));
    expect(result.reason, contains('older'));
  });

  test(
    'authorization, missing and rate limit remain distinct states',
    () async {
      for (final item in [
        (401, MarketState.failed, 'authorization'),
        (403, MarketState.failed, 'authorization'),
        (404, MarketState.missing, 'no intraday'),
        (429, MarketState.throttled, 'limit'),
      ]) {
        final gateway = FugleIntradayGateway(
          apiKeySource: () async => 'key',
          transport: FakeFugleTransport(
            (_, _) async => MarketResponse(item.$1, ''),
          ),
        );
        final result = await gateway.latestBar(
          twStock(),
          interval: IntradayInterval.oneMinute,
        );
        expect(result.state, item.$2);
        expect(result.reason, contains(item.$3));
      }
    },
  );

  test(
    'wrong series, malformed price and invalid credential fail closed',
    () async {
      for (final body in [
        oneMinuteResponse.replaceFirst('"market":"TSE"', '"market":"OTC"'),
        oneMinuteResponse.replaceFirst('"close":1322.5', '"close":0'),
        oneMinuteResponse.replaceFirst('"volume":594', '"volume":1.5'),
        oneMinuteResponse.replaceFirst('"high":1325.5', '"high":1300'),
        oneMinuteResponse.replaceFirst('09:01:00', '29:01:00'),
      ]) {
        final gateway = FugleIntradayGateway(
          apiKeySource: () async => 'key',
          transport: FakeFugleTransport(
            (_, _) async => MarketResponse(200, body),
          ),
          clock: () => DateTime.utc(2026, 9, 30, 1, 2),
        );
        expect(
          (await gateway.latestBar(
            twStock(),
            interval: IntradayInterval.oneMinute,
          )).state,
          MarketState.failed,
        );
      }
      final invalidKey = FugleIntradayGateway(
        apiKeySource: () async => 'bad key',
        transport: FakeFugleTransport(
          (_, _) async => const MarketResponse(200, oneMinuteResponse),
        ),
      );
      expect(
        (await invalidKey.latestBar(
          twStock(),
          interval: IntradayInterval.oneMinute,
        )).state,
        MarketState.failed,
      );
    },
  );

  test('latest timestamp wins even if provider order changes', () async {
    const earlier = '''{
      "date":"2026-09-30T09:00:00.000+08:00",
      "open":1310,"high":1312,"low":1308,"close":1311,"volume":12
    }''';
    final body = oneMinuteResponse.replaceFirst(
      '"data":[',
      '"data":[$earlier,',
    );
    final gateway = FugleIntradayGateway(
      apiKeySource: () async => 'key',
      transport: FakeFugleTransport((_, _) async => MarketResponse(200, body)),
      clock: () => DateTime.utc(2026, 9, 30, 1, 2),
    );
    final result = await gateway.latestBar(
      twStock(),
      interval: IntradayInterval.oneMinute,
    );
    expect(result.state, MarketState.available);
    expect(result.value!.startsAt.value, DateTime.utc(2026, 9, 30, 1, 1));
    expect(result.value!.close, '1322.5');
  });

  test(
    'unsupported instrument does not request credentials or network',
    () async {
      var keyCalls = 0;
      final transport = FakeFugleTransport(
        (_, _) async => const MarketResponse(200, oneMinuteResponse),
      );
      final gateway = FugleIntradayGateway(
        apiKeySource: () async {
          keyCalls++;
          return 'key';
        },
        transport: transport,
      );
      final result = await gateway.latestBar(
        twStock(market: 'XNAS', symbol: 'AAPL'),
        interval: IntradayInterval.oneMinute,
      );
      expect(result.state, MarketState.unsupported);
      expect(keyCalls, 0);
      expect(transport.requests, isEmpty);
    },
  );

  test('same instrument and interval share one in-flight request', () async {
    final completer = Completer<MarketResponse>();
    final transport = FakeFugleTransport((_, _) => completer.future);
    final gateway = FugleIntradayGateway(
      apiKeySource: () async => 'key',
      transport: transport,
      clock: () => DateTime.utc(2026, 9, 30, 1, 2),
    );
    final instrument = twStock();
    final first = gateway.latestBar(
      instrument,
      interval: IntradayInterval.oneMinute,
    );
    final second = gateway.latestBar(
      instrument,
      interval: IntradayInterval.oneMinute,
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.requests, hasLength(1));
    completer.complete(const MarketResponse(200, oneMinuteResponse));
    expect((await first).state, MarketState.available);
    expect((await second).state, MarketState.available);
  });

  test('Fugle adapter participates in provider registry and routing', () async {
    final provider = FugleIntradayStockProvider(
      FugleIntradayGateway(
        apiKeySource: () async => 'key',
        transport: FakeFugleTransport(
          (_, _) async => const MarketResponse(200, oneMinuteResponse),
        ),
        clock: () => DateTime.utc(2026, 9, 30, 1, 2),
      ),
    );
    final registry = MarketProviderRegistry([provider]);
    expect(provider.descriptor.requiresAuthorization, isTrue);
    expect(
      registry.intradayStockProviders(twStock(), IntradayInterval.oneMinute),
      [provider],
    );
    final result = await MarketDataRouter(registry)
        .intradayBar(twStock(), interval: IntradayInterval.oneMinute);
    expect(result.result.state, MarketState.available);
    expect(result.selectedProvider!.id, FugleIntradayStockProvider.providerId);
  });
}
