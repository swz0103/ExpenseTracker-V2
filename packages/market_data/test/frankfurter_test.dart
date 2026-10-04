import 'dart:async';

import 'package:foundation_values/foundation_values.dart';
import 'package:market_data/market_data.dart';
import 'package:test/test.dart';

final class _Transport implements MarketTransport {
  _Transport(this.response);

  final MarketResponse response;
  final requests = <Uri>[];

  @override
  Future<MarketResponse> get(Uri uri) async {
    requests.add(uri);
    return response;
  }
}

void main() {
  final eur = Currency('EUR', 2);
  final usd = Currency('USD', 2);
  final twd = Currency.of('TWD');
  final now = DateTime.utc(2026, 10, 1, 12);

  test(
    'no-key direct pair preserves exact decimal and provider date',
    () async {
      final transport = _Transport(
        const MarketResponse(
          200,
          '{"date":"2026-10-01","base":"EUR","quote":"USD","rate":1.13530}',
        ),
      );
      final gateway = FrankfurterReferenceFxGateway(
        transport: transport,
        clock: () => now,
      );
      final result = await gateway.rate(eur, usd);
      expect(result.state, MarketState.available);
      expect(result.value!.observation.rate.numerator, BigInt.from(11353));
      expect(result.value!.observation.rate.denominator, BigInt.from(10000));
      expect(result.value!.observation.asOf, BusinessDate(2026, 10, 1));
      expect(
        result.value!.observation.source,
        FrankfurterReferenceFxGateway.providerId,
      );
      expect(transport.requests.single.queryParameters, isEmpty);
    },
  );

  test(
    'historical query marks an earlier provider observation stale',
    () async {
      final transport = _Transport(
        const MarketResponse(
          200,
          '{"date":"2026-09-30","base":"USD","quote":"TWD","rate":31.852}',
        ),
      );
      final gateway = FrankfurterReferenceFxGateway(
        transport: transport,
        clock: () => now,
      );
      final result = await gateway.rate(
        usd,
        twd,
        requiredAsOf: BusinessDate(2026, 10, 1),
      );
      expect(result.state, MarketState.stale);
      expect(result.value!.observation.rate, FxRate.parse(usd, twd, '31.852'));
      expect(transport.requests.single.queryParameters['date'], '2026-10-01');
    },
  );

  test('JSON numbers become exact decimal text', () {
    expect(plainDecimal('6.14e-05'), '0.0000614');
    expect(plainDecimal('1.13530'), '1.1353');
    expect(plainDecimal('2E3'), '2000');
    expect(plainDecimal('0.5e1'), '5');
    expect(() => plainDecimal('-1'), throwsFormatException);
  });

  test('a tiny rate in exponent form is not misread', () async {
    final idr = Currency('IDR', 2);
    final transport = _Transport(
      const MarketResponse(
        200,
        '{"date":"2026-10-01","base":"IDR","quote":"USD",'
        '"rate":6.14e-05,"note":"added later"}',
      ),
    );
    final gateway = FrankfurterReferenceFxGateway(
      transport: transport,
      clock: () => now,
    );
    final result = await gateway.rate(idr, usd);
    expect(result.state, MarketState.available);
    expect(result.value!.observation.rate, FxRate.parse(idr, usd, '0.0000614'));
  });

  test('cache coalesces identical no-key requests', () async {
    final transport = _Transport(
      const MarketResponse(
        200,
        '{"date":"2026-10-01","base":"EUR","quote":"USD","rate":1.1}',
      ),
    );
    final gateway = FrankfurterReferenceFxGateway(
      transport: transport,
      clock: () => now,
    );
    final results = await Future.wait([
      gateway.rate(eur, usd),
      gateway.rate(eur, usd),
      gateway.rate(eur, usd),
    ]);
    expect(
      results.every((result) => result.state == MarketState.available),
      isTrue,
    );
    expect(transport.requests, hasLength(1));
  });

  test('HTTP states and malformed payload fail closed', () async {
    for (final entry in [
      (const MarketResponse(429, ''), MarketState.throttled),
      (const MarketResponse(404, ''), MarketState.missing),
      (const MarketResponse(500, ''), MarketState.failed),
      (
        const MarketResponse(
          200,
          '{"date":"2026-10-01","base":"EUR","quote":"USD","rate":"1.1"}',
        ),
        MarketState.failed,
      ),
    ]) {
      final result = await FrankfurterReferenceFxGateway(
        transport: _Transport(entry.$1),
        clock: () => now,
      ).rate(eur, usd);
      expect(result.state, entry.$2);
    }
  });

  test('provider is account-free and supports cross-currency pairs', () {
    final provider = FrankfurterReferenceFxProvider(
      FrankfurterReferenceFxGateway(
        transport: _Transport(const MarketResponse(500, '')),
        clock: () => now,
      ),
    );
    expect(provider.descriptor.requiresAuthorization, isFalse);
    expect(provider.supportsFx(eur, twd, historical: true), isTrue);
    expect(provider.supportsFx(eur, eur, historical: false), isFalse);
  });
}
