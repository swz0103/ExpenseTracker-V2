import 'dart:async';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';
import 'package:test/test.dart';

const response = '''{
  "meta":{
    "symbol":"AAPL",
    "interval":"1min",
    "currency":"USD",
    "exchange_timezone":"America/New_York",
    "exchange":"NASDAQ",
    "mic_code":"XNAS",
    "type":"Common Stock"
  },
  "values":[
    {"datetime":"2026-09-30 14:01:00","open":"226.10","high":"226.50","low":"226.00","close":"226.40","volume":"1250"},
    {"datetime":"2026-09-30 14:00:00","open":"225.90","high":"226.20","low":"225.80","close":"226.10","volume":"900"}
  ],
  "status":"ok"
}''';

final class FakeTransport implements TwelveDataTransport {
  FakeTransport(this.handle);
  final Future<MarketResponse> Function(Uri, String) handle;
  final requests = <(Uri, String)>[];

  @override
  Future<MarketResponse> get(Uri uri, {required String apiKey}) {
    requests.add((uri, apiKey));
    return handle(uri, apiKey);
  }
}

InvestmentInstrument stock({
  String market = 'XNAS',
  String symbol = 'AAPL',
  String currency = 'USD',
}) => InvestmentInstrument(
  id: PublicId.generate(),
  kind: InstrumentKind.stock,
  marketCode: market,
  symbol: symbol,
  name: symbol,
  tradingCurrency: Currency(currency, 2),
);

void main() {
  test('parses latest US one-minute bar and keeps key out of URI', () async {
    final transport = FakeTransport(
      (_, _) async => const MarketResponse(200, response),
    );
    final gateway = TwelveDataIntradayGateway(
      apiKeySource: () async => 'secret-key',
      transport: transport,
      clock: () => DateTime.utc(2026, 9, 30, 14, 2),
    );
    final result = await gateway.latestBar(
      stock(),
      interval: IntradayInterval.oneMinute,
    );
    expect(result.state, MarketState.available);
    expect(result.value!.close, '226.40');
    expect(result.value!.volume, BigInt.from(1250));
    expect(result.value!.startsAt.value, DateTime.utc(2026, 9, 30, 14, 1));
    final request = transport.requests.single;
    expect(request.$1.host, 'api.twelvedata.com');
    expect(request.$1.queryParameters['interval'], '1min');
    expect(request.$1.queryParameters['timezone'], 'UTC');
    expect(request.$1.queryParameters, isNot(contains('apikey')));
    expect(request.$2, 'secret-key');
  });

  test('five-minute request and stale threshold are explicit', () async {
    final body = response.replaceAll('"1min"', '"5min"');
    final transport = FakeTransport((_, _) async => MarketResponse(200, body));
    final gateway = TwelveDataIntradayGateway(
      apiKeySource: () async => 'key',
      transport: transport,
      clock: () => DateTime.utc(2026, 9, 30, 14, 8),
    );
    final result = await gateway.latestBar(
      stock(),
      interval: IntradayInterval.fiveMinutes,
    );
    expect(result.state, MarketState.stale);
    expect(transport.requests.single.$1.queryParameters['interval'], '5min');
  });

  test('HTTP and payload limits preserve distinct states', () async {
    for (final item in [
      (401, '', MarketState.failed),
      (404, '', MarketState.missing),
      (429, '', MarketState.throttled),
      (200, '{"status":"error","code":429}', MarketState.throttled),
      (200, '{"status":"error","code":404}', MarketState.missing),
      (200, '{"status":"error","code":401}', MarketState.failed),
    ]) {
      final gateway = TwelveDataIntradayGateway(
        apiKeySource: () async => 'key',
        transport: FakeTransport(
          (_, _) async => MarketResponse(item.$1, item.$2),
        ),
      );
      expect(
        (await gateway.latestBar(
          stock(),
          interval: IntradayInterval.oneMinute,
        )).state,
        item.$3,
      );
    }
  });

  test('wrong series and malformed bars fail closed', () async {
    for (final body in [
      response.replaceFirst('"mic_code":"XNAS"', '"mic_code":"XNYS"'),
      response.replaceFirst('"currency":"USD"', '"currency":"TWD"'),
      response.replaceFirst('"close":"226.40"', '"close":"0"'),
      response.replaceFirst('"high":"226.50"', '"high":"220"'),
      response.replaceFirst('"volume":"1250"', '"volume":"1.5"'),
      response.replaceFirst('2026-09-30 14:01:00', '2026-09-30T14:01:00Z'),
    ]) {
      final gateway = TwelveDataIntradayGateway(
        apiKeySource: () async => 'key',
        transport: FakeTransport((_, _) async => MarketResponse(200, body)),
        clock: () => DateTime.utc(2026, 9, 30, 14, 2),
      );
      expect(
        (await gateway.latestBar(
          stock(),
          interval: IntradayInterval.oneMinute,
        )).state,
        MarketState.failed,
      );
    }
  });

  test(
    'unsupported market, currency and symbol avoid key and network',
    () async {
      var keyCalls = 0;
      final transport = FakeTransport(
        (_, _) async => const MarketResponse(200, response),
      );
      final gateway = TwelveDataIntradayGateway(
        apiKeySource: () async {
          keyCalls++;
          return 'key';
        },
        transport: transport,
      );
      for (final instrument in [
        stock(market: 'TWSE', symbol: '2330', currency: 'TWD'),
        stock(currency: 'TWD'),
      stock(symbol: 'ABCDEFGHIJK'),
      ]) {
        expect(
          (await gateway.latestBar(
            instrument,
            interval: IntradayInterval.oneMinute,
          )).state,
          MarketState.unsupported,
        );
      }
      expect(keyCalls, 0);
      expect(transport.requests, isEmpty);
    },
  );

  test('identical concurrent lookup has one key read and request', () async {
    final pending = Completer<MarketResponse>();
    var keyCalls = 0;
    final transport = FakeTransport((_, _) => pending.future);
    final gateway = TwelveDataIntradayGateway(
      apiKeySource: () async {
        keyCalls++;
        return 'key';
      },
      transport: transport,
      clock: () => DateTime.utc(2026, 9, 30, 14, 2),
    );
    final instrument = stock();
    final first = gateway.latestBar(
      instrument,
      interval: IntradayInterval.oneMinute,
    );
    final second = gateway.latestBar(
      instrument,
      interval: IntradayInterval.oneMinute,
    );
    await Future<void>.delayed(Duration.zero);
    expect(keyCalls, 1);
    expect(transport.requests, hasLength(1));
    pending.complete(const MarketResponse(200, response));
    expect((await first).state, MarketState.available);
    expect((await second).state, MarketState.available);
  });

  test('Twelve Data provider registers only for supported US instruments', () {
    final provider = TwelveDataIntradayStockProvider(
      TwelveDataIntradayGateway(
        apiKeySource: () async => 'key',
        transport: FakeTransport(
          (_, _) async => const MarketResponse(200, response),
        ),
      ),
    );
    final registry = MarketProviderRegistry([provider]);
    expect(provider.descriptor.requiresAuthorization, isTrue);
    expect(
      registry.intradayStockProviders(stock(), IntradayInterval.oneMinute),
      [provider],
    );
    expect(
      registry.intradayStockProviders(
        stock(market: 'TWSE', symbol: '2330', currency: 'TWD'),
        IntradayInterval.oneMinute,
      ),
      isEmpty,
    );
  });
}
