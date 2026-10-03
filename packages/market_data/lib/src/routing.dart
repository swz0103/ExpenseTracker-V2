import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';

import 'intraday.dart';
import 'frankfurter.dart';
import 'market_data.dart';
import 'twelve_data.dart';
import 'yahoo_chart.dart';

final class MarketProviderDescriptor {
  MarketProviderDescriptor({
    required this.id,
    required this.label,
    required this.dataset,
    required this.attribution,
    required this.requiresAuthorization,
  }) {
    _validateId(id);
    if (label.trim().isEmpty ||
        dataset.trim().isEmpty ||
        attribution.trim().isEmpty) {
      throw ArgumentError('Provider metadata must not be empty');
    }
  }

  final String id;
  final String label;
  final String dataset;
  final String attribution;
  final bool requiresAuthorization;
}

abstract interface class MarketDataProvider {
  MarketProviderDescriptor get descriptor;
}

abstract interface class StockCloseProvider implements MarketDataProvider {
  bool supportsStockClose(InvestmentInstrument instrument);

  Future<MarketResult<StockClose>> stockClose(
    InvestmentInstrument instrument, {
    BusinessDate? requiredAsOf,
  });
}

abstract interface class IntradayStockProvider implements MarketDataProvider {
  bool supportsIntraday(
    InvestmentInstrument instrument,
    IntradayInterval interval,
  );

  Future<MarketResult<IntradayBar>> latestBar(
    InvestmentInstrument instrument, {
    required IntradayInterval interval,
  });
}

abstract interface class ReferenceFxProvider implements MarketDataProvider {
  bool supportsFx(Currency base, Currency quote, {required bool historical});

  Future<MarketResult<ReferenceRate>> fxRate(
    Currency base,
    Currency quote, {
    BusinessDate? requiredAsOf,
  });

  Future<MarketResult<ReferenceRate>> historicalFxRate(
    Currency base,
    Currency quote, {
    required BusinessDate date,
    int lookbackDays = 7,
  });
}

final class TwseStockCloseProvider implements StockCloseProvider {
  TwseStockCloseProvider(this.gateway);

  final MarketDataGateway gateway;

  @override
  MarketProviderDescriptor get descriptor => MarketProviderDescriptor(
    id: StockClose.provider,
    label: '臺灣證券交易所',
    dataset: 'STOCK_DAY_ALL',
    attribution: '臺灣證券交易所 OpenAPI／政府資料開放授權條款第 1 版',
    requiresAuthorization: false,
  );

  @override
  bool supportsStockClose(InvestmentInstrument instrument) =>
      instrument.marketCode == 'TWSE' &&
      instrument.tradingCurrency == Currency.of('TWD');

  @override
  Future<MarketResult<StockClose>> stockClose(
    InvestmentInstrument instrument, {
    BusinessDate? requiredAsOf,
  }) => gateway.stockClose(instrument, requiredAsOf: requiredAsOf);
}

final class TpexStockCloseProvider implements StockCloseProvider {
  TpexStockCloseProvider(this.gateway);

  static const providerId = 'tpex-mainboard-daily-close-quotes';
  final MarketDataGateway gateway;

  @override
  MarketProviderDescriptor get descriptor => MarketProviderDescriptor(
    id: providerId,
    label: '證券櫃檯買賣中心',
    dataset: 'tpex_mainboard_daily_close_quotes',
    attribution: '證券櫃檯買賣中心 OpenAPI／政府資料開放授權條款第 1 版',
    requiresAuthorization: false,
  );

  @override
  bool supportsStockClose(InvestmentInstrument instrument) =>
      instrument.marketCode == 'TPEX' &&
      instrument.tradingCurrency == Currency.of('TWD');

  @override
  Future<MarketResult<StockClose>> stockClose(
    InvestmentInstrument instrument, {
    BusinessDate? requiredAsOf,
  }) => gateway.tpexStockClose(instrument, requiredAsOf: requiredAsOf);
}

final class FugleIntradayStockProvider implements IntradayStockProvider {
  FugleIntradayStockProvider(this.gateway);

  static const providerId = 'fugle-tw-intraday';
  final FugleIntradayGateway gateway;

  @override
  MarketProviderDescriptor get descriptor => MarketProviderDescriptor(
    id: providerId,
    label: 'Fugle 富果行情',
    dataset: '台股日內 K 線（1／5 分鐘）',
    attribution: 'Fugle MarketData API；實際使用受帳戶方案與資料授權約束',
    requiresAuthorization: true,
  );

  @override
  bool supportsIntraday(
    InvestmentInstrument instrument,
    IntradayInterval interval,
  ) =>
      (instrument.marketCode == 'TWSE' || instrument.marketCode == 'TPEX') &&
      instrument.tradingCurrency == Currency.of('TWD');

  @override
  Future<MarketResult<IntradayBar>> latestBar(
    InvestmentInstrument instrument, {
    required IntradayInterval interval,
  }) => gateway.latestBar(instrument, interval: interval);
}

final class TwelveDataIntradayStockProvider implements IntradayStockProvider {
  TwelveDataIntradayStockProvider(this.gateway);

  static const providerId = 'twelve-data-us-intraday';
  final TwelveDataIntradayGateway gateway;

  @override
  MarketProviderDescriptor get descriptor => MarketProviderDescriptor(
    id: providerId,
    label: 'Twelve Data',
    dataset: 'US equities intraday time series (1／5 minute)',
    attribution: 'Twelve Data；實際使用受帳戶方案與資料顯示授權約束',
    requiresAuthorization: true,
  );

  @override
  bool supportsIntraday(
    InvestmentInstrument instrument,
    IntradayInterval interval,
  ) => supportsTwelveDataInstrument(instrument);

  @override
  Future<MarketResult<IntradayBar>> latestBar(
    InvestmentInstrument instrument, {
    required IntradayInterval interval,
  }) => gateway.latestBar(instrument, interval: interval);
}

/// Opt-in only (ADR-06, health check G2-17): the App never registers this
/// provider by default. A user may turn it on for personal use after seeing
/// the [MarketProviderDescriptor.attribution] disclaimer; it must never be
/// the first or only source for background alerts.
final class YahooChartIntradayStockProvider implements IntradayStockProvider {
  YahooChartIntradayStockProvider(this.gateway);

  static const providerId = 'yahoo-chart-best-effort-intraday';
  final YahooChartIntradayGateway gateway;

  @override
  MarketProviderDescriptor get descriptor => MarketProviderDescriptor(
    id: providerId,
    label: 'Yahoo Finance（免金鑰／非保證）',
    dataset: 'Undocumented public chart endpoint (1／5 minute)',
    attribution: 'Yahoo Finance；非正式公開 API，可能延遲、限流、變更或停止',
    requiresAuthorization: false,
  );

  @override
  bool supportsIntraday(
    InvestmentInstrument instrument,
    IntradayInterval interval,
  ) => gateway.supports(instrument);

  @override
  Future<MarketResult<IntradayBar>> latestBar(
    InvestmentInstrument instrument, {
    required IntradayInterval interval,
  }) => gateway.latestBar(instrument, interval: interval);
}

final class EcbReferenceFxProvider implements ReferenceFxProvider {
  EcbReferenceFxProvider(this.gateway);

  final MarketDataGateway gateway;

  @override
  MarketProviderDescriptor get descriptor => MarketProviderDescriptor(
    id: ReferenceRate.provider,
    label: '歐洲中央銀行',
    dataset: 'EXR daily reference rates',
    attribution:
        'European Central Bank reference rates; inversion is disclosed',
    requiresAuthorization: false,
  );

  @override
  bool supportsFx(Currency base, Currency quote, {required bool historical}) {
    const currencies = {'USD', 'JPY', 'GBP', 'CHF'};
    return (base.code == 'EUR' && currencies.contains(quote.code)) ||
        (quote.code == 'EUR' && currencies.contains(base.code));
  }

  @override
  Future<MarketResult<ReferenceRate>> fxRate(
    Currency base,
    Currency quote, {
    BusinessDate? requiredAsOf,
  }) => gateway.fxRate(base, quote, requiredAsOf: requiredAsOf);

  @override
  Future<MarketResult<ReferenceRate>> historicalFxRate(
    Currency base,
    Currency quote, {
    required BusinessDate date,
    int lookbackDays = 7,
  }) => gateway.historicalFxRate(
    base,
    quote,
    date: date,
    lookbackDays: lookbackDays,
  );
}

final class CbcUsdTwdReferenceFxProvider implements ReferenceFxProvider {
  CbcUsdTwdReferenceFxProvider(this.gateway);

  static const providerId = 'cbc-usd-twd-daily-close';
  final MarketDataGateway gateway;

  @override
  MarketProviderDescriptor get descriptor => MarketProviderDescriptor(
    id: providerId,
    label: '中華民國中央銀行',
    dataset: '銀行間市場新臺幣對美元收盤匯率（日）',
    attribution: '中央銀行；資料來源：台北外匯經紀股份有限公司／政府資料開放授權條款第 1 版',
    requiresAuthorization: false,
  );

  @override
  bool supportsFx(Currency base, Currency quote, {required bool historical}) =>
      (base == Currency('USD', 2) && quote == Currency.of('TWD')) ||
      (base == Currency.of('TWD') && quote == Currency('USD', 2));

  @override
  Future<MarketResult<ReferenceRate>> fxRate(
    Currency base,
    Currency quote, {
    BusinessDate? requiredAsOf,
  }) => gateway.cbcUsdTwdRate(base, quote, requiredAsOf: requiredAsOf);

  @override
  Future<MarketResult<ReferenceRate>> historicalFxRate(
    Currency base,
    Currency quote, {
    required BusinessDate date,
    int lookbackDays = 7,
  }) => gateway.historicalCbcUsdTwdRate(
    base,
    quote,
    date: date,
    lookbackDays: lookbackDays,
  );
}

final class FrankfurterReferenceFxProvider implements ReferenceFxProvider {
  FrankfurterReferenceFxProvider(this.gateway);

  final FrankfurterReferenceFxGateway gateway;

  @override
  MarketProviderDescriptor get descriptor => MarketProviderDescriptor(
    id: FrankfurterReferenceFxGateway.providerId,
    label: 'Frankfurter 公開匯率',
    dataset: 'v2 central-bank reference rates',
    attribution: 'Frankfurter；各匯率仍受原始央行或官方來源條款約束',
    requiresAuthorization: false,
  );

  @override
  bool supportsFx(Currency base, Currency quote, {required bool historical}) =>
      base != quote;

  @override
  Future<MarketResult<ReferenceRate>> fxRate(
    Currency base,
    Currency quote, {
    BusinessDate? requiredAsOf,
  }) => gateway.rate(base, quote, requiredAsOf: requiredAsOf);

  @override
  Future<MarketResult<ReferenceRate>> historicalFxRate(
    Currency base,
    Currency quote, {
    required BusinessDate date,
    int lookbackDays = 7,
  }) async {
    if (lookbackDays < 0 || lookbackDays > 7) {
      throw RangeError.range(lookbackDays, 0, 7, 'lookbackDays');
    }
    // Frankfurter answers with the latest rate on or before the date, which
    // can be months old for a dropped pair (health check G2-10).
    final result = await gateway.rate(base, quote, requiredAsOf: date);
    final asOf = result.value?.observation.asOf;
    if (asOf == null) return result;
    final requested = DateTime.utc(date.year, date.month, date.day);
    final observed = DateTime.utc(asOf.year, asOf.month, asOf.day);
    if (requested.difference(observed).inDays > lookbackDays) {
      return MarketResult(
        MarketState.missing,
        reason: 'Frankfurter has no rate within $lookbackDays days',
      );
    }
    return result;
  }
}

final class MarketProviderRegistry {
  MarketProviderRegistry(Iterable<MarketDataProvider> providers)
    : _providers = _index(providers);

  final Map<String, MarketDataProvider> _providers;

  List<MarketProviderDescriptor> get providers => _providers.values
      .map((provider) => provider.descriptor)
      .toList(growable: false);

  MarketDataProvider provider(String id) {
    final result = _providers[id];
    if (result == null) throw StateError('Unknown market data provider');
    return result;
  }

  List<StockCloseProvider> stockCloseProviders(
    InvestmentInstrument instrument,
  ) => _providers.values
      .whereType<StockCloseProvider>()
      .where((provider) => provider.supportsStockClose(instrument))
      .toList(growable: false);

  List<IntradayStockProvider> intradayStockProviders(
    InvestmentInstrument instrument,
    IntradayInterval interval,
  ) => _providers.values
      .whereType<IntradayStockProvider>()
      .where((provider) => provider.supportsIntraday(instrument, interval))
      .toList(growable: false);

  List<ReferenceFxProvider> fxProviders(
    Currency base,
    Currency quote, {
    required bool historical,
  }) => _providers.values
      .whereType<ReferenceFxProvider>()
      .where(
        (provider) => provider.supportsFx(base, quote, historical: historical),
      )
      .toList(growable: false);

  static Map<String, MarketDataProvider> _index(
    Iterable<MarketDataProvider> providers,
  ) {
    final result = <String, MarketDataProvider>{};
    for (final provider in providers) {
      final id = provider.descriptor.id;
      _validateId(id);
      if (result.containsKey(id)) throw StateError('Duplicate provider ID');
      result[id] = provider;
    }
    if (result.isEmpty)
      throw ArgumentError('At least one provider is required');
    return Map.unmodifiable(result);
  }
}

enum MarketRoutingMode { automatic, fixed }

final class MarketRoutingPolicy {
  const MarketRoutingPolicy.automatic({this.preferredProviderIds = const []})
    : mode = MarketRoutingMode.automatic,
      fixedProviderId = null;

  const MarketRoutingPolicy.fixed(String providerId)
    : mode = MarketRoutingMode.fixed,
      fixedProviderId = providerId,
      preferredProviderIds = const [];

  final MarketRoutingMode mode;
  final String? fixedProviderId;
  final List<String> preferredProviderIds;
}

final class MarketProviderAttempt {
  const MarketProviderAttempt({
    required this.provider,
    required this.state,
    required this.reason,
  });

  final MarketProviderDescriptor provider;
  final MarketState state;
  final String? reason;
}

final class RoutedMarketResult<T> {
  const RoutedMarketResult({
    required this.result,
    required this.selectedProvider,
    required this.attempts,
  });

  final MarketResult<T> result;
  final MarketProviderDescriptor? selectedProvider;
  final List<MarketProviderAttempt> attempts;

  bool get usedFallback => selectedProvider != null && attempts.length > 1;
}

final class MarketCrossCheckItem<T> {
  const MarketCrossCheckItem({required this.provider, required this.result});

  final MarketProviderDescriptor provider;
  final MarketResult<T> result;
}

final class MarketCrossCheck<T> {
  const MarketCrossCheck({
    required this.items,
    required this.conflict,
    this.reason,
  });

  final List<MarketCrossCheckItem<T>> items;
  final bool conflict;
  final String? reason;
}

final class MarketDataRouter {
  const MarketDataRouter(this.registry);

  final MarketProviderRegistry registry;

  Future<RoutedMarketResult<StockClose>> stockClose(
    InvestmentInstrument instrument, {
    BusinessDate? requiredAsOf,
    MarketRoutingPolicy policy = const MarketRoutingPolicy.automatic(),
  }) async {
    final providers = _ordered(
      registry.stockCloseProviders(instrument),
      policy,
    );
    return _route<StockCloseProvider, StockClose>(
      providers,
      (provider) => provider.stockClose(instrument, requiredAsOf: requiredAsOf),
    );
  }

  Future<RoutedMarketResult<IntradayBar>> intradayBar(
    InvestmentInstrument instrument, {
    required IntradayInterval interval,
    MarketRoutingPolicy policy = const MarketRoutingPolicy.automatic(),
  }) async {
    final providers = _ordered(
      registry.intradayStockProviders(instrument, interval),
      policy,
    );
    return _route<IntradayStockProvider, IntradayBar>(
      providers,
      (provider) => provider.latestBar(instrument, interval: interval),
    );
  }

  Future<RoutedMarketResult<ReferenceRate>> fxRate(
    Currency base,
    Currency quote, {
    BusinessDate? requiredAsOf,
    MarketRoutingPolicy policy = const MarketRoutingPolicy.automatic(),
  }) async {
    final providers = _ordered(
      registry.fxProviders(base, quote, historical: false),
      policy,
    );
    return _route<ReferenceFxProvider, ReferenceRate>(
      providers,
      (provider) => provider.fxRate(base, quote, requiredAsOf: requiredAsOf),
    );
  }

  Future<RoutedMarketResult<ReferenceRate>> historicalFxRate(
    Currency base,
    Currency quote, {
    required BusinessDate date,
    int lookbackDays = 7,
    MarketRoutingPolicy policy = const MarketRoutingPolicy.automatic(),
  }) async {
    final providers = _ordered(
      registry.fxProviders(base, quote, historical: true),
      policy,
    );
    return _route<ReferenceFxProvider, ReferenceRate>(
      providers,
      (provider) => provider.historicalFxRate(
        base,
        quote,
        date: date,
        lookbackDays: lookbackDays,
      ),
    );
  }

  Future<MarketCrossCheck<StockClose>> crossCheckStockClose(
    InvestmentInstrument instrument, {
    BusinessDate? requiredAsOf,
  }) async {
    final providers = registry.stockCloseProviders(instrument);
    final items = await Future.wait([
      for (final provider in providers)
        _crossItem(
          provider,
          () => provider.stockClose(instrument, requiredAsOf: requiredAsOf),
        ),
    ]);
    final usable = items
        .where((item) => item.result.value != null)
        .toList(growable: false);
    final conflict =
        usable.length > 1 &&
        usable
            .skip(1)
            .any(
              (item) => !_sameStockClose(
                usable.first.result.value!,
                item.result.value!,
              ),
            );
    return MarketCrossCheck(
      items: List.unmodifiable(items),
      conflict: conflict,
      reason: conflict
          ? 'Providers disagree on observation date or closing price'
          : null,
    );
  }

  Future<MarketCrossCheck<ReferenceRate>> crossCheckFxRate(
    Currency base,
    Currency quote, {
    BusinessDate? requiredAsOf,
  }) async {
    final providers = registry.fxProviders(base, quote, historical: false);
    final items = await Future.wait([
      for (final provider in providers)
        _crossItem(
          provider,
          () => provider.fxRate(base, quote, requiredAsOf: requiredAsOf),
        ),
    ]);
    final usable = items
        .where((item) => item.result.value != null)
        .toList(growable: false);
    final conflict =
        usable.length > 1 &&
        usable
            .skip(1)
            .any(
              (item) => !_sameReferenceRate(
                usable.first.result.value!,
                item.result.value!,
              ),
            );
    return MarketCrossCheck(
      items: List.unmodifiable(items),
      conflict: conflict,
      reason: conflict
          ? 'Providers disagree on observation date, pair, rate or derivation'
          : null,
    );
  }

  Future<MarketCrossCheckItem<T>> _crossItem<P extends MarketDataProvider, T>(
    P provider,
    Future<MarketResult<T>> Function() fetch,
  ) async {
    try {
      return MarketCrossCheckItem(
        provider: provider.descriptor,
        result: await fetch(),
      );
    } catch (_) {
      return MarketCrossCheckItem(
        provider: provider.descriptor,
        result: const MarketResult(
          MarketState.failed,
          reason: 'Provider request failed',
        ),
      );
    }
  }
}

Future<RoutedMarketResult<T>> _route<P extends MarketDataProvider, T>(
  List<P> providers,
  Future<MarketResult<T>> Function(P provider) fetch,
) async {
  if (providers.isEmpty) {
    return const RoutedMarketResult(
      result: MarketResult(
        MarketState.unsupported,
        reason: 'No registered provider supports this query',
      ),
      selectedProvider: null,
      attempts: [],
    );
  }
  final attempts = <MarketProviderAttempt>[];
  MarketResult<T>? stale;
  MarketProviderDescriptor? staleProvider;
  MarketResult<T>? last;
  for (final provider in providers) {
    late final MarketResult<T> result;
    try {
      result = await fetch(provider);
    } catch (_) {
      result = const MarketResult(
        MarketState.failed,
        reason: 'Provider request failed',
      );
    }
    attempts.add(
      MarketProviderAttempt(
        provider: provider.descriptor,
        state: result.state,
        reason: result.reason,
      ),
    );
    last = result;
    if (result.state == MarketState.available && result.value != null) {
      return RoutedMarketResult(
        result: result,
        selectedProvider: provider.descriptor,
        attempts: List.unmodifiable(attempts),
      );
    }
    if (stale == null &&
        result.state == MarketState.stale &&
        result.value != null) {
      stale = result;
      staleProvider = provider.descriptor;
    }
  }
  return RoutedMarketResult(
    result:
        stale ??
        last ??
        const MarketResult(
          MarketState.unsupported,
          reason: 'No provider result',
        ),
    selectedProvider: staleProvider,
    attempts: List.unmodifiable(attempts),
  );
}

List<P> _ordered<P extends MarketDataProvider>(
  List<P> providers,
  MarketRoutingPolicy policy,
) {
  if (policy.mode == MarketRoutingMode.fixed) {
    return providers
        .where((provider) => provider.descriptor.id == policy.fixedProviderId)
        .toList(growable: false);
  }
  final preferred = <String, int>{};
  for (var i = 0; i < policy.preferredProviderIds.length; i++) {
    final id = policy.preferredProviderIds[i];
    if (preferred.containsKey(id)) throw ArgumentError('Duplicate preference');
    preferred[id] = i;
  }
  final indexed = providers.indexed.toList();
  indexed.sort((a, b) {
    final aPriority = preferred[a.$2.descriptor.id];
    final bPriority = preferred[b.$2.descriptor.id];
    if (aPriority != null && bPriority != null) {
      return aPriority.compareTo(bPriority);
    }
    if (aPriority != null) return -1;
    if (bPriority != null) return 1;
    return a.$1.compareTo(b.$1);
  });
  return indexed.map((item) => item.$2).toList(growable: false);
}

bool _sameStockClose(StockClose a, StockClose b) =>
    a.symbol == b.symbol &&
    a.asOf == b.asOf &&
    _canonicalDecimal(a.decimalPrice) == _canonicalDecimal(b.decimalPrice);

/// Central banks publish slightly different reference rates for the same
/// day, so only a gap over half a percent is a disagreement (health check
/// G2-22).
bool _sameReferenceRate(ReferenceRate a, ReferenceRate b) {
  final x = a.observation.rate;
  final y = b.observation.rate;
  if (a.observation.asOf != b.observation.asOf ||
      x.base != y.base ||
      x.quote != y.quote) {
    return false;
  }
  final cross = x.numerator * y.denominator;
  final gap = (cross - y.numerator * x.denominator).abs();
  return gap * BigInt.from(200) <= cross;
}

String _canonicalDecimal(String value) {
  final parts = value.split('.');
  if (parts.length == 1) return '${BigInt.parse(parts.single)}';
  if (parts.length != 2) return value;
  final fraction = parts[1].replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty
      ? '${BigInt.parse(parts[0])}'
      : '${BigInt.parse(parts[0])}.$fraction';
}

void _validateId(String value) {
  if (value.isEmpty ||
      value.length > 100 ||
      !RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(value)) {
    throw ArgumentError.value(value, 'providerId');
  }
}
