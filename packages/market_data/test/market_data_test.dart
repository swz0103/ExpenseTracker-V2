import 'dart:async';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';
import 'package:test/test.dart';

const twseRows = '''[
  {"Date":"1150929","Code":"2330","Name":"台積電","ClosingPrice":"1,234.50"},
  {"Date":"1150929","Code":"0050","Name":"元大台灣50","ClosingPrice":"62.75"},
  {"Date":"1150929","Code":"2317","Name":"鴻海","ClosingPrice":"--"}
]''';

const ecbCsv = '''KEY,FREQ,CURRENCY,CURRENCY_DENOM,EXR_TYPE,EXR_SUFFIX,TIME_PERIOD,OBS_VALUE
EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2026-09-29,1.12345
''';

const historicalEcbCsv = '''KEY,FREQ,CURRENCY,CURRENCY_DENOM,EXR_TYPE,EXR_SUFFIX,TIME_PERIOD,OBS_VALUE
EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2020-01-03,1.12345
EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2020-01-01,
EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2020-01-02,1.00001
''';

final class FakeTransport implements MarketTransport {
  FakeTransport(this.handle);
  final Future<MarketResponse> Function(Uri) handle;
  final requests = <Uri>[];
  @override
  Future<MarketResponse> get(Uri uri) {
    requests.add(uri);
    return handle(uri);
  }
}

InvestmentInstrument instrument(
  String symbol,
  InstrumentKind kind, {
  String market = 'TWSE',
}) => InvestmentInstrument(
  id: PublicId.generate(),
  kind: kind,
  marketCode: market,
  symbol: symbol,
  name: symbol,
  tradingCurrency: Currency('TWD', 2),
);

void main() {
  late DateTime now;
  setUp(() => now = DateTime.utc(2026, 9, 30, 4));

  test(
    'TWSE exact decimal, ROC date, stock and ETF share one snapshot',
    () async {
      final transport = FakeTransport(
        (_) async => const MarketResponse(200, twseRows),
      );
      final gateway = MarketDataGateway(transport: transport, clock: () => now);
      final stock = await gateway.stockClose(
        instrument('2330', InstrumentKind.stock),
      );
      final etf = await gateway.stockClose(
        instrument('0050', InstrumentKind.etf),
      );
      expect(stock.state, MarketState.available);
      expect(stock.value!.decimalPrice, '1234.50');
      expect(stock.value!.asOf.toString(), '2026-09-29');
      expect(stock.value!.fetchedAt.value, now);
      expect(StockClose.provider, 'twse-stock-day-all');
      expect(etf.value!.decimalPrice, '62.75');
      expect(transport.requests, [MarketDataGateway.twseUri]);
    },
  );

  test(
    'TWSE missing price, absent symbol, unsupported market, stale date',
    () async {
      final transport = FakeTransport(
        (_) async => const MarketResponse(200, twseRows),
      );
      final gateway = MarketDataGateway(transport: transport, clock: () => now);
      expect(
        (await gateway.stockClose(instrument('2317', InstrumentKind.stock)))
            .state,
        MarketState.missing,
      );
      expect(
        (await gateway.stockClose(instrument('2454', InstrumentKind.stock)))
            .state,
        MarketState.missing,
      );
      expect(
        (await gateway.stockClose(
          instrument('2330', InstrumentKind.stock, market: 'TPEX'),
        )).state,
        MarketState.unsupported,
      );
      final stale = await gateway.stockClose(
        instrument('2330', InstrumentKind.stock),
        requiredAsOf: BusinessDate(2026, 9, 30),
      );
      expect(stale.state, MarketState.stale);
      expect(stale.value!.asOf.toString(), '2026-09-29');
      expect(transport.requests.length, 1);
    },
  );

  test('malformed and duplicate TWSE rows fail closed', () async {
    for (final body in [
      '[{"Code":"2330","Date":"1150230","ClosingPrice":"1"}]',
      '[{"Code":"2330","Date":"1150929","ClosingPrice":1.2}]',
      '[{"Code":"2330","Date":"1150929","ClosingPrice":"1,23.4"}]',
      '[{"Code":"2330","Date":"1150929","ClosingPrice":"2"},'
          '{"Code":"2330","Date":"1150929","ClosingPrice":"3"}]',
    ]) {
      final gateway = MarketDataGateway(
        transport: FakeTransport((_) async => MarketResponse(200, body)),
        clock: () => now,
      );
      expect(
        (await gateway.stockClose(instrument('2330', InstrumentKind.stock)))
            .state,
        MarketState.failed,
      );
    }
  });

  test(
    'ECB exact EUR base rate and derived inverse preserve exact ratio',
    () async {
      final transport = FakeTransport(
        (_) async => const MarketResponse(200, ecbCsv),
      );
      final gateway = MarketDataGateway(transport: transport, clock: () => now);
      final eur = Currency('EUR', 2);
      final usd = Currency('USD', 2);
      final direct = await gateway.fxRate(eur, usd);
      final inverse = await gateway.fxRate(usd, eur);
      expect(direct.state, MarketState.available);
      expect(direct.value!.observation.rate.numerator, BigInt.from(22469));
      expect(direct.value!.observation.rate.denominator, BigInt.from(20000));
      expect(direct.value!.observation.asOf.toString(), '2026-09-29');
      expect(direct.value!.observation.source, ReferenceRate.provider);
      expect(direct.value!.derivedInverse, isFalse);
      expect(inverse.value!.observation.rate.numerator, BigInt.from(20000));
      expect(inverse.value!.observation.rate.denominator, BigInt.from(22469));
      expect(inverse.value!.derivedInverse, isTrue);
      expect(transport.requests.length, 1);
      expect(
        transport.requests.single.path,
        '/service/data/EXR/D.USD.EUR.SP00.A',
      );
      expect(
        transport.requests.single.queryParameters['lastNObservations'],
        '1',
      );
    },
  );

  test(
    'ECB requested day is exact; empty, wrong series and unsupported pair',
    () async {
      final eur = Currency('EUR', 2);
      final usd = Currency('USD', 2);
      final date = BusinessDate(2026, 9, 30);
      final transport = FakeTransport(
        (_) async => const MarketResponse(200, ecbCsv),
      );
      final gateway = MarketDataGateway(transport: transport, clock: () => now);
      expect(
        (await gateway.fxRate(eur, usd, requiredAsOf: date)).state,
        MarketState.missing,
      );
      expect(
        transport.requests.single.queryParameters['startPeriod'],
        date.toString(),
      );
      final missing = MarketDataGateway(
        transport: FakeTransport((_) async => const MarketResponse(404, '')),
        clock: () => now,
      );
      expect(
        (await missing.fxRate(eur, usd, requiredAsOf: date)).state,
        MarketState.missing,
      );
      final wrong = MarketDataGateway(
        transport: FakeTransport(
          (_) async => const MarketResponse(
            200,
            'FREQ,CURRENCY,CURRENCY_DENOM,EXR_TYPE,EXR_SUFFIX,TIME_PERIOD,OBS_VALUE\nD,GBP,EUR,SP00,A,2026-09-29,1.2\n',
          ),
        ),
        clock: () => now,
      );
      expect((await wrong.fxRate(eur, usd)).state, MarketState.failed);
      expect(
        (await gateway.fxRate(usd, Currency('TWD', 2))).state,
        MarketState.unsupported,
      );
    },
  );

  test(
    'cooldown, cache expiration, provider failure and stale fallback',
    () async {
      var fails = false;
      final transport = FakeTransport(
        (_) async => fails
            ? const MarketResponse(503, '')
            : const MarketResponse(200, twseRows),
      );
      final gateway = MarketDataGateway(
        transport: transport,
        clock: () => now,
        cacheTtl: const Duration(minutes: 1),
        requestCooldown: const Duration(minutes: 2),
      );
      final stock = instrument('2330', InstrumentKind.stock);
      expect((await gateway.stockClose(stock)).state, MarketState.available);
      now = now.add(const Duration(minutes: 1));
      expect((await gateway.stockClose(stock)).state, MarketState.stale);
      expect(transport.requests.length, 1);
      now = now.add(const Duration(minutes: 2));
      fails = true;
      final stale = await gateway.stockClose(stock);
      expect(stale.state, MarketState.stale);
      expect(stale.value!.fetchedAt.value, DateTime.utc(2026, 9, 30, 4));
      expect(transport.requests.length, 2);
    },
  );

  test('single-flight lookup and no-data throttling', () async {
    final completer = Completer<MarketResponse>();
    final transport = FakeTransport((_) => completer.future);
    final gateway = MarketDataGateway(transport: transport, clock: () => now);
    final a = gateway.stockClose(instrument('2330', InstrumentKind.stock));
    final b = gateway.stockClose(instrument('0050', InstrumentKind.etf));
    await Future<void>.delayed(Duration.zero);
    expect(transport.requests.length, 1);
    completer.complete(const MarketResponse(429, ''));
    expect((await a).state, MarketState.throttled);
    expect((await b).state, MarketState.throttled);
    expect(
      (await gateway.stockClose(instrument('2330', InstrumentKind.stock)))
          .state,
      MarketState.throttled,
    );
    expect(transport.requests.length, 1);
  });

  test(
    'ECB cooldown is shared across series, not bypassed by changing pair',
    () async {
      final transport = FakeTransport(
        (_) async => const MarketResponse(200, ecbCsv),
      );
      final gateway = MarketDataGateway(transport: transport, clock: () => now);
      expect(
        (await gateway.fxRate(Currency('EUR', 2), Currency('USD', 2))).state,
        MarketState.available,
      );
      expect(
        (await gateway.fxRate(Currency('EUR', 2), Currency('JPY', 0))).state,
        MarketState.throttled,
      );
      expect(transport.requests.length, 1);
    },
  );

  test(
    'historical ECB selects latest published observation and marks gap stale',
    () async {
      final transport = FakeTransport(
        (_) async => const MarketResponse(200, historicalEcbCsv),
      );
      final gateway = MarketDataGateway(transport: transport, clock: () => now);
      final result = await gateway.historicalFxRate(
        Currency('USD', 2),
        Currency('EUR', 2),
        date: BusinessDate(2020, 1, 5),
      );
      expect(result.state, MarketState.stale);
      expect(result.reason, contains('predates'));
      expect(result.value!.observation.asOf, BusinessDate(2020, 1, 3));
      expect(result.value!.observation.retrievedAt.value, now);
      expect(result.value!.observation.source, ReferenceRate.provider);
      expect(result.value!.derivedInverse, isTrue);
      expect(result.value!.observation.rate.numerator, BigInt.from(20000));
      expect(result.value!.observation.rate.denominator, BigInt.from(22469));
      final uri = transport.requests.single;
      expect(uri.path, '/service/data/EXR/D.USD.EUR.SP00.A');
      expect(uri.queryParameters['startPeriod'], '2019-12-29');
      expect(uri.queryParameters['endPeriod'], '2020-01-05');
      expect(uri.queryParameters, isNot(contains('lastNObservations')));
    },
  );

  test('historical exact date is available even when years old', () async {
    final gateway = MarketDataGateway(
      transport: FakeTransport(
        (_) async => const MarketResponse(200, historicalEcbCsv),
      ),
      clock: () => now,
    );
    final result = await gateway.historicalFxRate(
      Currency('EUR', 2),
      Currency('USD', 2),
      date: BusinessDate(2020, 1, 3),
    );
    expect(result.state, MarketState.available);
    expect(result.value!.observation.asOf, BusinessDate(2020, 1, 3));
    expect(result.value!.derivedInverse, isFalse);
  });

  test(
    'historical gap, outside-range and unsupported pair fail honestly',
    () async {
      final empty = MarketDataGateway(
        transport: FakeTransport((_) async => const MarketResponse(404, '')),
        clock: () => now,
      );
      expect(
        (await empty.historicalFxRate(
          Currency('EUR', 2),
          Currency('USD', 2),
          date: BusinessDate(2020, 1, 5),
        )).state,
        MarketState.missing,
      );
      final wrong = MarketDataGateway(
        transport: FakeTransport(
          (_) async => const MarketResponse(200, historicalEcbCsv),
        ),
        clock: () => now,
      );
      expect(
        (await wrong.historicalFxRate(
          Currency('EUR', 2),
          Currency('USD', 2),
          date: BusinessDate(2020, 1, 5),
          lookbackDays: 1,
        )).state,
        MarketState.failed,
      );
      expect(
        (await wrong.historicalFxRate(
          Currency('USD', 2),
          Currency('TWD', 2),
          date: BusinessDate(2020, 1, 5),
        )).state,
        MarketState.unsupported,
      );
      expect(
        () => wrong.historicalFxRate(
          Currency('EUR', 2),
          Currency('USD', 2),
          date: BusinessDate(2020, 1, 5),
          lookbackDays: 8,
        ),
        throwsRangeError,
      );
    },
  );

  test(
    'historical provider failure preserves dated cache only as stale',
    () async {
      var fails = false;
      final transport = FakeTransport(
        (_) async => fails
            ? const MarketResponse(503, '')
            : const MarketResponse(200, historicalEcbCsv),
      );
      final gateway = MarketDataGateway(
        transport: transport,
        clock: () => now,
        cacheTtl: const Duration(minutes: 1),
        requestCooldown: Duration.zero,
      );
      final eur = Currency('EUR', 2);
      final usd = Currency('USD', 2);
      final date = BusinessDate(2020, 1, 3);
      expect(
        (await gateway.historicalFxRate(eur, usd, date: date)).state,
        MarketState.available,
      );
      now = now.add(const Duration(minutes: 2));
      fails = true;
      final stale = await gateway.historicalFxRate(eur, usd, date: date);
      expect(stale.state, MarketState.stale);
      expect(stale.value!.observation.asOf, date);
      expect(
        stale.value!.observation.retrievedAt.value,
        DateTime.utc(2026, 9, 30, 4),
      );
      expect(transport.requests.length, 2);

      final noCache = MarketDataGateway(
        transport: FakeTransport((_) async => const MarketResponse(503, '')),
        clock: () => now,
      );
      expect(
        (await noCache.historicalFxRate(eur, usd, date: date)).state,
        MarketState.failed,
      );
    },
  );
}
