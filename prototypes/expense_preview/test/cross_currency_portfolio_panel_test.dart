import 'package:expense_preview/cross_currency_portfolio_panel.dart';
import 'package:expense_preview/privacy_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';

InvestmentPositionPerformance _position({
  required Currency currency,
  required String cost,
  required String price,
}) {
  final account = PublicId.generate();
  final instrument = PublicId.generate();
  return InvestmentPositionPerformance(
    investmentAccountId: account,
    instrumentId: instrument,
    tradingCurrency: currency,
    performance: InvestmentPerformance.calculate(
      investmentAccountId: account,
      instrumentId: instrument,
      currency: currency,
      openLots: [
        InvestmentHoldingLot(
          id: PublicId.generate(),
          investmentAccountId: account,
          instrumentId: instrument,
          acquiredOn: BusinessDate(2026, 9, 29),
          remainingQuantity: ShareQuantity.parse('1'),
          remainingCost: Money.parse(currency, cost),
          expectedVersion: 1,
        ),
      ],
      realizedResults: const [],
      netDividends: const [],
      usablePrice: ShareUnitPrice.parse(currency, price),
    ),
  );
}

ReferenceRate _rate({
  required Currency base,
  required Currency quote,
  required String decimal,
  required BusinessDate asOf,
  bool inverse = false,
}) => ReferenceRate(
  observation: FxObservation(
    rate: FxRate.parse(base, quote, decimal),
    source: 'test-reference-rate',
    asOf: asOf,
    retrievedAt: UtcInstant(DateTime.utc(2026, 9, 30, 8)),
  ),
  derivedInverse: inverse,
);

final class _FxProvider implements ReferenceFxProvider {
  _FxProvider(this.result);

  final MarketResult<ReferenceRate> result;
  var latestCalls = 0;
  var historicalCalls = 0;

  @override
  MarketProviderDescriptor get descriptor => MarketProviderDescriptor(
    id: 'test-fx-provider',
    label: '測試匯率來源',
    dataset: '測試匯率資料集',
    attribution: '測試來源註記',
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
  }) async {
    latestCalls++;
    return result;
  }

  @override
  Future<MarketResult<ReferenceRate>> historicalFxRate(
    Currency base,
    Currency quote, {
    required BusinessDate date,
    int lookbackDays = 7,
  }) async {
    historicalCalls++;
    return result;
  }
}

final class _Controller implements CrossCurrencyPortfolioController {
  _Controller(this.read, this.reportingCurrencies);

  final CrossCurrencyPortfolioRead read;
  @override
  final List<Currency> reportingCurrencies;
  int calls = 0;
  bool? lastAllowEarlier;

  @override
  Future<CrossCurrencyPortfolioRead> load({
    required Currency reportingCurrency,
    required bool allowEarlier,
  }) async {
    calls++;
    lastAllowEarlier = allowEarlier;
    return read;
  }
}

void main() {
  final usd = Currency('USD', 2);
  final twd = Currency('TWD', 2);
  final date = BusinessDate(2026, 9, 30);

  InvestmentPortfolioSummary portfolio() =>
      InvestmentPortfolioSummary.calculate([
        _position(currency: usd, cost: '10', price: '12'),
        _position(currency: twd, cost: '100', price: '110'),
      ]);

  CrossCurrencyPortfolioRead read({
    bool includeRate = true,
    BusinessDate? asOf,
    bool providerInverse = false,
  }) {
    final provider = _FxProvider(
      MarketResult(
        MarketState.available,
        value: _rate(
          base: usd,
          quote: twd,
          decimal: '32',
          asOf: asOf ?? date,
          inverse: providerInverse,
        ),
      ),
    );
    final descriptor = provider.descriptor;
    final reference = provider.result.value!;
    return CrossCurrencyPortfolioRead(
      summary: CrossCurrencyInvestmentSummary.convert(
        original: portfolio(),
        reportingCurrency: twd,
        valuationDate: date,
        observations: includeRate
            ? [
                PortfolioFxInput(
                  observation: reference.observation,
                  derivedInverse: reference.derivedInverse,
                ),
              ]
            : const [],
        allowEarlier: asOf != null && asOf != date,
      ),
      routes: {
        usd: RoutedMarketResult(
          result: includeRate
              ? provider.result
              : const MarketResult(MarketState.missing, reason: '指定日無可用匯率'),
          selectedProvider: includeRate ? descriptor : null,
          attempts: [
            MarketProviderAttempt(
              provider: descriptor,
              state: includeRate ? MarketState.available : MarketState.missing,
              reason: includeRate ? null : '指定日無可用匯率',
            ),
          ],
        ),
      },
    );
  }

  Future<void> show(
    WidgetTester tester,
    _Controller controller, {
    PrivacyMode privacy = PrivacyMode.visible,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CrossCurrencyPortfolioPanel(
          controller: controller,
          privacy: privacy,
        ),
      ),
    ),
  );

  test(
    'routed controller keeps selected source and inverse provenance',
    () async {
      final provider = _FxProvider(
        MarketResult(
          MarketState.available,
          value: _rate(
            base: usd,
            quote: twd,
            decimal: '32',
            asOf: date,
            inverse: true,
          ),
        ),
      );
      final controller = RoutedCrossCurrencyPortfolioController(
        original: portfolio(),
        router: MarketDataRouter(MarketProviderRegistry([provider])),
        valuationDate: date,
        reportingCurrencies: [twd],
      );
      final result = await controller.load(
        reportingCurrency: twd,
        allowEarlier: false,
      );
      expect(provider.latestCalls, 1);
      expect(provider.historicalCalls, 0);
      expect(result.summary.marketValue, Money.parse(twd, '494'));
      expect(result.summary.rows[usd]!.derivedInverse, isTrue);
      expect(result.routes[usd]!.selectedProvider!.id, 'test-fx-provider');
    },
  );

  testWidgets('complete summary shows totals and source provenance', (
    tester,
  ) async {
    final controller = _Controller(read(providerInverse: true), [twd]);
    await show(tester, controller);
    await tester.tap(find.byKey(const ValueKey('load-cross-currency-summary')));
    await tester.pumpAndSettle();
    expect(find.text('匯率資料完整'), findsOneWidget);
    expect(find.text('合計剩餘成本 TWD 420.00'), findsOneWidget);
    expect(find.text('合計參考市值 TWD 494.00'), findsOneWidget);
    expect(find.text('實際來源：測試匯率來源'), findsOneWidget);
    expect(find.text('Provider ID：test-reference-rate'), findsOneWidget);
    expect(find.text('觀測日：2026-09-30'), findsOneWidget);
    expect(find.text('衍生方式：使用來源匯率的反向值'), findsOneWidget);
  });

  testWidgets('missing rate hides all cross-currency grand totals', (
    tester,
  ) async {
    final controller = _Controller(read(includeRate: false), [twd]);
    await show(tester, controller);
    await tester.tap(find.byKey(const ValueKey('load-cross-currency-summary')));
    await tester.pumpAndSettle();
    expect(find.textContaining('跨幣總額不可用'), findsOneWidget);
    expect(find.textContaining('合計剩餘成本'), findsNothing);
    expect(find.text('來源狀態：指定日無可用匯率'), findsOneWidget);
  });

  testWidgets('earlier-rate opt-in reaches controller and keeps date visible', (
    tester,
  ) async {
    final controller = _Controller(read(asOf: BusinessDate(2026, 9, 29)), [
      twd,
    ]);
    await show(tester, controller);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('load-cross-currency-summary')));
    await tester.pumpAndSettle();
    expect(controller.lastAllowEarlier, isTrue);
    expect(find.textContaining('較早匯率'), findsOneWidget);
    expect(find.text('觀測日：2026-09-29'), findsOneWidget);
  });

  testWidgets('hidden privacy mode performs no read', (tester) async {
    final controller = _Controller(read(), [twd]);
    await show(tester, controller, privacy: PrivacyMode.hidden);
    expect(find.text('跨幣別投資摘要已隱藏。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('load-cross-currency-summary')),
      findsNothing,
    );
    expect(controller.calls, 0);
  });
}
