import 'dart:collection';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';
import 'package:test/test.dart';

void main() {
  final instrument = InvestmentInstrument(
    id: PublicId.generate(),
    kind: InstrumentKind.stock,
    marketCode: 'TWSE',
    symbol: '2330',
    name: 'TSMC',
    tradingCurrency: Currency.of('TWD'),
  );
  final asOf = BusinessDate(2026, 9, 30);

  test('registry keeps multiple providers and rejects duplicate identity', () {
    final first = _StockProvider('first', []);
    final second = _StockProvider('second', []);
    final registry = MarketProviderRegistry([first, second]);
    expect(registry.providers.map((item) => item.id), ['first', 'second']);
    expect(registry.stockCloseProviders(instrument), [first, second]);
    expect(() => MarketProviderRegistry([first, first]), throwsStateError);
  });

  test('automatic route falls back and retains every attempt', () async {
    final first = _StockProvider('first', [
      const MarketResult(MarketState.failed, reason: 'offline'),
    ]);
    final second = _StockProvider('second', [
      MarketResult(MarketState.available, value: _close('100.00', asOf)),
    ]);
    final result = await MarketDataRouter(
      MarketProviderRegistry([first, second]),
    ).stockClose(instrument);
    expect(result.result.value!.decimalPrice, '100.00');
    expect(result.selectedProvider!.id, 'second');
    expect(result.usedFallback, isTrue);
    expect(result.attempts.map((item) => item.state), [
      MarketState.failed,
      MarketState.available,
    ]);
    expect(result.selectedProvider!.dataset, 'dataset-second');
    expect(result.selectedProvider!.attribution, 'attribution-second');
  });

  test('fixed route never silently switches provider', () async {
    final first = _StockProvider('first', [
      const MarketResult(MarketState.throttled, reason: 'limited'),
    ]);
    final second = _StockProvider('second', [
      MarketResult(MarketState.available, value: _close('100', asOf)),
    ]);
    final result = await MarketDataRouter(
      MarketProviderRegistry([first, second]),
    ).stockClose(instrument, policy: const MarketRoutingPolicy.fixed('first'));
    expect(result.result.state, MarketState.throttled);
    expect(result.selectedProvider, isNull);
    expect(result.attempts, hasLength(1));
    expect(second.calls, 0);
  });

  test('preferred order is explicit and fresh result stops fallback', () async {
    final first = _StockProvider('first', [
      MarketResult(MarketState.available, value: _close('99', asOf)),
    ]);
    final second = _StockProvider('second', [
      MarketResult(MarketState.available, value: _close('100', asOf)),
    ]);
    final result =
        await MarketDataRouter(MarketProviderRegistry([first, second]))
            .stockClose(
              instrument,
              policy: const MarketRoutingPolicy.automatic(
                preferredProviderIds: ['second', 'first'],
              ),
            );
    expect(result.selectedProvider!.id, 'second');
    expect(result.attempts, hasLength(1));
    expect(first.calls, 0);
  });

  test(
    'stale observation is retained only when no fresh source succeeds',
    () async {
      final first = _StockProvider('first', [
        MarketResult(MarketState.stale, value: _close('98', asOf)),
      ]);
      final second = _StockProvider('second', [
        const MarketResult(MarketState.missing, reason: 'holiday'),
      ]);
      final result = await MarketDataRouter(
        MarketProviderRegistry([first, second]),
      ).stockClose(instrument);
      expect(result.result.state, MarketState.stale);
      expect(result.result.value!.decimalPrice, '98');
      expect(result.selectedProvider!.id, 'first');
      expect(result.attempts, hasLength(2));
    },
  );

  test('cross-check does not average and flags real disagreements', () async {
    final equalA = _StockProvider('a', [
      MarketResult(MarketState.available, value: _close('100.0', asOf)),
    ]);
    final equalB = _StockProvider('b', [
      MarketResult(MarketState.available, value: _close('100.00', asOf)),
    ]);
    final equal = await MarketDataRouter(
      MarketProviderRegistry([equalA, equalB]),
    ).crossCheckStockClose(instrument);
    expect(equal.conflict, isFalse);
    expect(equal.items, hasLength(2));

    final conflictA = _StockProvider('a', [
      MarketResult(MarketState.available, value: _close('100', asOf)),
    ]);
    final conflictB = _StockProvider('b', [
      MarketResult(MarketState.available, value: _close('101', asOf)),
    ]);
    final conflict = await MarketDataRouter(
      MarketProviderRegistry([conflictA, conflictB]),
    ).crossCheckStockClose(instrument);
    expect(conflict.conflict, isTrue);
    expect(conflict.reason, contains('disagree'));
    expect(conflict.items.map((item) => item.result.value!.decimalPrice), [
      '100',
      '101',
    ]);
  });

  test('FX cross-check includes rate date and inversion derivation', () async {
    final eur = Currency('EUR', 2);
    final usd = Currency('USD', 2);
    final first = _FxProvider('fx-a', [
      MarketResult(
        MarketState.available,
        value: _rate(eur, usd, '1.1', asOf, inverse: false),
      ),
    ]);
    final second = _FxProvider('fx-b', [
      MarketResult(
        MarketState.available,
        value: _rate(eur, usd, '1.1', asOf, inverse: true),
      ),
    ]);
    final result = await MarketDataRouter(
      MarketProviderRegistry([first, second]),
    ).crossCheckFxRate(eur, usd, requiredAsOf: asOf);
    expect(result.conflict, isTrue);
    expect(result.items.map((item) => item.provider.id), ['fx-a', 'fx-b']);
  });

  test('official adapters register as independent capabilities', () {
    final gateway = MarketDataGateway(
      transport: _NoNetworkTransport(),
      clock: () => DateTime.utc(2026, 9, 30),
    );
    final registry = MarketProviderRegistry([
      TwseStockCloseProvider(gateway),
      TpexStockCloseProvider(gateway),
      EcbReferenceFxProvider(gateway),
      CbcUsdTwdReferenceFxProvider(gateway),
    ]);
    expect(registry.stockCloseProviders(instrument), hasLength(1));
    final tpex = InvestmentInstrument(
      id: PublicId.generate(),
      kind: InstrumentKind.stock,
      marketCode: 'TPEX',
      symbol: '6488',
      name: 'GlobalWafers',
      tradingCurrency: Currency.of('TWD'),
    );
    expect(registry.stockCloseProviders(tpex), hasLength(1));
    expect(
      registry.fxProviders(
        Currency('EUR', 2),
        Currency('USD', 2),
        historical: true,
      ),
      hasLength(1),
    );
    expect(
      registry.fxProviders(
        Currency('USD', 2),
        Currency.of('TWD'),
        historical: true,
      ),
      hasLength(1),
    );
  });
}

StockClose _close(String price, BusinessDate asOf) => StockClose(
  symbol: '2330',
  decimalPrice: price,
  asOf: asOf,
  fetchedAt: UtcInstant(DateTime.utc(2026, 9, 30, 8)),
);

ReferenceRate _rate(
  Currency base,
  Currency quote,
  String rate,
  BusinessDate asOf, {
  required bool inverse,
}) => ReferenceRate(
  observation: FxObservation(
    rate: FxRate.parse(base, quote, rate),
    source: 'test',
    asOf: asOf,
    retrievedAt: UtcInstant(DateTime.utc(2026, 9, 30, 8)),
  ),
  derivedInverse: inverse,
);

final class _StockProvider implements StockCloseProvider {
  _StockProvider(this.id, Iterable<MarketResult<StockClose>> results)
    : results = Queue.of(results);

  final String id;
  final Queue<MarketResult<StockClose>> results;
  var calls = 0;

  @override
  MarketProviderDescriptor get descriptor => MarketProviderDescriptor(
    id: id,
    label: 'Provider $id',
    dataset: 'dataset-$id',
    attribution: 'attribution-$id',
    requiresAuthorization: false,
  );

  @override
  bool supportsStockClose(InvestmentInstrument instrument) => true;

  @override
  Future<MarketResult<StockClose>> stockClose(
    InvestmentInstrument instrument, {
    BusinessDate? requiredAsOf,
  }) async {
    calls++;
    return results.removeFirst();
  }
}

final class _FxProvider implements ReferenceFxProvider {
  _FxProvider(this.id, Iterable<MarketResult<ReferenceRate>> results)
    : results = Queue.of(results);

  final String id;
  final Queue<MarketResult<ReferenceRate>> results;

  @override
  MarketProviderDescriptor get descriptor => MarketProviderDescriptor(
    id: id,
    label: 'Provider $id',
    dataset: 'dataset-$id',
    attribution: 'attribution-$id',
    requiresAuthorization: false,
  );

  @override
  bool supportsFx(Currency base, Currency quote, {required bool historical}) =>
      true;

  @override
  Future<MarketResult<ReferenceRate>> fxRate(
    Currency base,
    Currency quote, {
    BusinessDate? requiredAsOf,
  }) async => results.removeFirst();

  @override
  Future<MarketResult<ReferenceRate>> historicalFxRate(
    Currency base,
    Currency quote, {
    required BusinessDate date,
    int lookbackDays = 7,
  }) async => results.removeFirst();
}

final class _NoNetworkTransport implements MarketTransport {
  @override
  Future<MarketResponse> get(Uri uri) => throw StateError('not called');
}
