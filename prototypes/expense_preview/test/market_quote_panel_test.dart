import 'dart:async';

import 'package:expense_preview/market_quote_panel.dart';
import 'package:expense_preview/price_alert_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';

const rows = '''[
  {"Date":"1150929","Code":"2330","Name":"測試上市股","ClosingPrice":"1,234.50"}
]''';

final class _Transport implements MarketTransport {
  _Transport(this.body);
  final String body;
  int calls = 0;

  @override
  Future<MarketResponse> get(Uri uri) async {
    calls++;
    return MarketResponse(200, body);
  }
}

final class _SequenceTransport implements MarketTransport {
  _SequenceTransport(this.bodies);
  final List<String> bodies;
  int calls = 0;

  @override
  Future<MarketResponse> get(Uri uri) async =>
      MarketResponse(200, bodies[calls++]);
}

final class _AlertStore implements PriceAlertRecordStore {
  final values = <PublicId, String>{};
  Completer<void>? readGate;

  @override
  Future<String?> read(PublicId instrumentId) async {
    await readGate?.future;
    return values[instrumentId];
  }

  @override
  Future<void> write(PublicId instrumentId, String value) async {
    values[instrumentId] = value;
  }

  @override
  Future<void> delete(PublicId instrumentId) async {
    values.remove(instrumentId);
  }
}

final class _AlertPresenter implements PriceAlertNotificationPresenter {
  final shown = <PriceAlertNotification>[];

  @override
  Future<bool> show(PriceAlertNotification notification) async {
    shown.add(notification);
    return true;
  }
}

void main() {
  final instrument = InvestmentInstrument(
    id: PublicId.generate(),
    kind: InstrumentKind.stock,
    marketCode: 'TWSE',
    symbol: '2330',
    name: '合成上市股',
    tradingCurrency: Currency('TWD', 2),
  );
  final accountId = PublicId.generate();
  final lots = [
    InvestmentHoldingLot(
      id: PublicId.generate(),
      investmentAccountId: accountId,
      instrumentId: instrument.id,
      acquiredOn: BusinessDate(2026, 1, 1),
      remainingQuantity: ShareQuantity.parse('2'),
      remainingCost: Money.parse(Currency('TWD', 2), '2000.00'),
      expectedVersion: 1,
    ),
  ];

  Future<void> show(
    WidgetTester tester,
    MarketDataGateway gateway, {
    bool visible = true,
    InvestmentInstrument? selected,
    bool holdings = false,
    bool history = false,
    BusinessDate? latestPositionDate,
    PriceAlertService? priceAlerts,
    PriceAlertNotificationPresenter? priceAlertNotifications,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MarketQuotePanel(
          instrument: selected ?? instrument,
          showAmounts: visible,
          investmentAccountId: holdings ? accountId : null,
          openLots: holdings ? lots : null,
          realizedResults: history
              ? [Money.parse(instrument.tradingCurrency, '100.00')]
              : const [],
          netDividends: history
              ? [Money.parse(instrument.tradingCurrency, '20.00')]
              : const [],
          historicalCashFlows: history
              ? [
                  InvestmentCashFlow(
                    BusinessDate(2026, 1, 1),
                    Money.parse(instrument.tradingCurrency, '-2500.00'),
                  ),
                  InvestmentCashFlow(
                    BusinessDate(2026, 3, 1),
                    Money.parse(instrument.tradingCurrency, '600.00'),
                  ),
                  InvestmentCashFlow(
                    BusinessDate(2026, 6, 1),
                    Money.parse(instrument.tradingCurrency, '20.00'),
                  ),
                ]
              : const [],
          latestPositionDate: latestPositionDate,
          gateway: gateway,
          priceAlerts: priceAlerts,
          priceAlertNotifications: priceAlertNotifications,
        ),
      ),
    ),
  );

  testWidgets('reference quote requires an explicit tap and shows provenance', (
    tester,
  ) async {
    final transport = _Transport(rows);
    final gateway = MarketDataGateway(
      transport: transport,
      clock: () => DateTime.utc(2026, 9, 30, 4),
    );
    await show(tester, gateway, holdings: true);
    expect(transport.calls, 0);
    await tester.tap(find.byKey(const ValueKey('request-market-close')));
    await tester.pumpAndSettle();
    expect(transport.calls, 1);
    expect(find.textContaining('1234.50 TWD'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('market-holding-value')))
          .data,
      contains('2469.00 TWD'),
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('market-unrealized'))).data,
      contains('469.00 TWD'),
    );
    expect(find.textContaining('交易日 2026-09-29'), findsOneWidget);
    expect(find.textContaining('台灣證交所'), findsWidgets);
  });

  testWidgets('stale quote is labeled and privacy clears it', (tester) async {
    final gateway = MarketDataGateway(
      transport: _Transport(rows),
      clock: () => DateTime.utc(2026, 10, 10),
    );
    await show(tester, gateway, holdings: true);
    await tester.tap(find.byKey(const ValueKey('request-market-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('market-close-stale')), findsOneWidget);
    expect(find.byKey(const ValueKey('market-close-value')), findsNothing);
    expect(find.byKey(const ValueKey('market-holding-value')), findsNothing);
    await show(tester, gateway, visible: false);
    expect(find.textContaining('1234.50'), findsNothing);
    expect(find.textContaining('隱私模式'), findsOneWidget);
    await show(tester, gateway);
    expect(find.textContaining('1234.50'), findsNothing);
  });

  testWidgets('committed gain and dividend join current mark and XIRR', (
    tester,
  ) async {
    final gateway = MarketDataGateway(
      transport: _Transport(rows),
      clock: () => DateTime.utc(2026, 9, 30, 4),
    );
    await show(tester, gateway, holdings: true, history: true);
    expect(find.byKey(const ValueKey('market-total-return')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('request-market-close')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('market-total-return')))
          .data,
      contains('589.00 TWD'),
    );
    expect(find.byKey(const ValueKey('market-xirr')), findsOneWidget);
    expect(find.textContaining('年化報酬率約'), findsOneWidget);
  });

  testWidgets('newly loaded history reuses an unchanged sourced close', (
    tester,
  ) async {
    final transport = _Transport(rows);
    final gateway = MarketDataGateway(
      transport: transport,
      clock: () => DateTime.utc(2026, 9, 30, 4),
    );
    await show(tester, gateway, holdings: true);
    await tester.tap(find.byKey(const ValueKey('request-market-close')));
    await tester.pumpAndSettle();
    expect(transport.calls, 1);
    await show(tester, gateway, holdings: true, history: true);
    expect(transport.calls, 1);
    expect(find.byKey(const ValueKey('market-close-source')), findsOneWidget);
    expect(find.byKey(const ValueKey('market-total-return')), findsOneWidget);
  });

  testWidgets('a pre-split close cannot value post-split shares', (
    tester,
  ) async {
    final gateway = MarketDataGateway(
      transport: _Transport(rows),
      clock: () => DateTime.utc(2026, 9, 30, 4),
    );
    await show(
      tester,
      gateway,
      holdings: true,
      latestPositionDate: BusinessDate(2026, 9, 30),
    );
    await tester.tap(find.byKey(const ValueKey('request-market-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('market-close-source')), findsOneWidget);
    expect(find.byKey(const ValueKey('market-holding-value')), findsNothing);
    expect(find.textContaining('早於最新交易'), findsOneWidget);
  });

  testWidgets('unsupported market does not request a provider', (tester) async {
    final transport = _Transport(rows);
    final gateway = MarketDataGateway(transport: transport);
    final unsupported = InvestmentInstrument(
      id: PublicId.generate(),
      kind: InstrumentKind.stock,
      marketCode: 'XNAS',
      symbol: 'TEST',
      name: '合成股票',
      tradingCurrency: Currency('USD', 2),
    );
    await show(tester, gateway, selected: unsupported);
    await tester.tap(find.byKey(const ValueKey('request-market-close')));
    await tester.pumpAndSettle();
    expect(transport.calls, 0);
    expect(find.textContaining('尚無行情來源'), findsOneWidget);
  });

  testWidgets('price alert can be saved and removed from quote panel', (
    tester,
  ) async {
    final store = _AlertStore();
    final alerts = PriceAlertService(store);
    await show(
      tester,
      MarketDataGateway(transport: _Transport(rows)),
      priceAlerts: alerts,
    );
    await tester.tap(find.byKey(const ValueKey('price-alert-section')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('price-alert-target')),
      '1500.25',
    );
    await tester.tap(find.byKey(const ValueKey('save-price-alert')));
    await tester.pumpAndSettle();
    expect(find.textContaining('提醒已儲存'), findsOneWidget);
    expect((await alerts.load(instrument))!.alert.target.toString(), '1500.25');
    await tester.tap(find.byKey(const ValueKey('delete-price-alert')));
    await tester.pumpAndSettle();
    expect(find.text('提醒已移除。'), findsOneWidget);
    expect(await alerts.load(instrument), isNull);
  });

  testWidgets('privacy mode does not expose saved price alert amount', (
    tester,
  ) async {
    final alerts = PriceAlertService(_AlertStore());
    await alerts.save(
      instrument: instrument,
      target: ShareUnitPrice.parse(instrument.tradingCurrency, '1500.25'),
      direction: PriceAlertDirection.atOrAbove,
    );
    await show(
      tester,
      MarketDataGateway(transport: _Transport(rows)),
      visible: false,
      priceAlerts: alerts,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('price-alert-section')), findsNothing);
    expect(find.textContaining('1500.25'), findsNothing);
  });

  testWidgets('crossing a saved threshold emits a system notification', (
    tester,
  ) async {
    final alerts = PriceAlertService(_AlertStore());
    final presenter = _AlertPresenter();
    await alerts.save(
      instrument: instrument,
      target: ShareUnitPrice.parse(instrument.tradingCurrency, '1500'),
      direction: PriceAlertDirection.atOrAbove,
    );
    var now = DateTime.utc(2026, 9, 30, 4);
    final transport = _SequenceTransport([
      '[{"Date":"1150929","Code":"2330","Name":"測試上市股","ClosingPrice":"1400"}]',
      '[{"Date":"1150930","Code":"2330","Name":"測試上市股","ClosingPrice":"1600"}]',
    ]);
    final gateway = MarketDataGateway(
      transport: transport,
      clock: () => now,
      cacheTtl: const Duration(microseconds: 1),
    );
    await show(
      tester,
      gateway,
      priceAlerts: alerts,
      priceAlertNotifications: presenter,
    );
    await tester.tap(find.byKey(const ValueKey('request-market-close')));
    await tester.pumpAndSettle();
    expect(presenter.shown, isEmpty);
    now = DateTime.utc(2026, 10, 1, 4);
    await tester.tap(find.byKey(const ValueKey('request-market-close')));
    await tester.pumpAndSettle();
    expect(presenter.shown.single.price, '1600');
    await tester.tap(find.byKey(const ValueKey('price-alert-section')));
    await tester.pumpAndSettle();
    expect(find.textContaining('到價提醒：2330 現在是 1600 TWD'), findsOneWidget);
  });

  testWidgets('privacy switch suppresses a late price notification', (
    tester,
  ) async {
    final store = _AlertStore();
    final alerts = PriceAlertService(store);
    final presenter = _AlertPresenter();
    await alerts.save(
      instrument: instrument,
      target: ShareUnitPrice.parse(instrument.tradingCurrency, '1200'),
      direction: PriceAlertDirection.atOrAbove,
    );
    await alerts.evaluate(
      instrument: instrument,
      result: MarketResult(
        MarketState.available,
        value: StockClose(
          symbol: instrument.symbol,
          decimalPrice: '1100',
          asOf: BusinessDate(2026, 9, 28),
          fetchedAt: UtcInstant(DateTime.utc(2026, 9, 28)),
        ),
      ),
      providerId: StockClose.provider,
      now: UtcInstant(DateTime.utc(2026, 9, 28)),
    );
    final gateway = MarketDataGateway(
      transport: _Transport(rows),
      clock: () => DateTime.utc(2026, 9, 30, 4),
    );
    await show(
      tester,
      gateway,
      priceAlerts: alerts,
      priceAlertNotifications: presenter,
    );
    await tester.pumpAndSettle();
    store.readGate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('request-market-close')));
    await tester.pump();
    await show(
      tester,
      gateway,
      visible: false,
      priceAlerts: alerts,
      priceAlertNotifications: presenter,
    );
    store.readGate!.complete();
    await tester.pumpAndSettle();
    expect(presenter.shown, isEmpty);
    expect(find.textContaining('1234.50'), findsNothing);
    expect(
      (await alerts.load(instrument))!.checkpoint.lastRelation,
      PriceRelation.below,
    );
  });
}
