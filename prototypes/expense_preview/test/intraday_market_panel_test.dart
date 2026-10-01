import 'package:expense_preview/intraday_market_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:market_data/market_data.dart';

final class _Timer implements IntradayRefreshTimer {
  @override
  void cancel() {}
}

final provider = MarketProviderDescriptor(
  id: 'fugle-test',
  label: 'Fugle 測試來源',
  dataset: '1／5 分鐘 K 線',
  attribution: '測試來源註記',
  requiresAuthorization: true,
);

IntradayBar _bar(IntradayInterval interval) => IntradayBar(
  symbol: '2330',
  interval: interval,
  startsAt: UtcInstant(DateTime.utc(2026, 9, 30, 1, 1)),
  open: '1310',
  high: '1325',
  low: '1305',
  close: '1322.5',
  volume: BigInt.from(594),
  fetchedAt: UtcInstant(DateTime.utc(2026, 9, 30, 1, 2)),
);

final class _Factory implements IntradayRefreshControllerFactory {
  IntradayInterval? interval;
  Duration? refreshEvery;
  MarketState state = MarketState.available;
  MarketProviderDescriptor selectedProvider = provider;

  @override
  IntradayRefreshController create({
    required IntradayInterval interval,
    required Duration refreshEvery,
  }) {
    this.interval = interval;
    this.refreshEvery = refreshEvery;
    return IntradayRefreshController(
      fetch: () async => RoutedMarketResult(
        result: state == MarketState.available
            ? MarketResult(MarketState.available, value: _bar(interval))
            : MarketResult(state, reason: '供應商暫時受限'),
        selectedProvider: state == MarketState.available
            ? selectedProvider
            : null,
        attempts: [
          MarketProviderAttempt(
            provider: provider,
            state: state,
            reason: state == MarketState.available ? null : '稍後重試',
          ),
        ],
      ),
      policy: IntradayRefreshPolicy(refreshEvery: refreshEvery),
      clock: () => DateTime.utc(2026, 9, 30, 1, 2),
      scheduler: (_, _) => _Timer(),
    );
  }
}

void main() {
  testWidgets('starts immediately and shows price, provenance and next retry', (
    tester,
  ) async {
    final factory = _Factory();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IntradayMarketPanel(factory: factory)),
      ),
    );
    await tester.tap(find.text('開始更新'));
    await tester.pump();
    await tester.pump();
    expect(find.text('最新價：1322.5'), findsOneWidget);
    expect(find.text('實際來源：Fugle 測試來源'), findsOneWidget);
    expect(find.text('資料集：1／5 分鐘 K 線'), findsOneWidget);
    expect(find.text('來源註記：測試來源註記'), findsOneWidget);
    expect(find.textContaining('下次嘗試：'), findsOneWidget);
    expect(find.text('停止更新'), findsOneWidget);
    expect(find.text('盤中行情只供估值參考，不會改寫成交、成本、換匯或現金。'), findsOneWidget);
  });

  testWidgets('five-minute bar and three-minute refresh reach the factory', (
    tester,
  ) async {
    final factory = _Factory();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IntradayMarketPanel(factory: factory)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('intraday-bar-interval')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 分鐘').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('intraday-refresh-interval')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每 3 分鐘').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始更新'));
    await tester.pump();
    expect(factory.interval, IntradayInterval.fiveMinutes);
    expect(factory.refreshEvery, const Duration(minutes: 3));
  });

  testWidgets('throttled state is visible and stopping releases controls', (
    tester,
  ) async {
    final factory = _Factory()..state = MarketState.throttled;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IntradayMarketPanel(factory: factory)),
      ),
    );
    await tester.tap(find.text('開始更新'));
    await tester.pump();
    await tester.pump();
    expect(find.text('狀態：暫時受限'), findsOneWidget);
    expect(find.textContaining('已自動降低請求頻率'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('intraday-attempt-fugle-test')),
      findsOneWidget,
    );
    await tester.tap(find.text('停止更新'));
    await tester.pumpAndSettle();
    expect(find.text('開始更新'), findsOneWidget);
  });

  testWidgets('Twelve Data selection shows the free quota warning', (
    tester,
  ) async {
    final factory = _Factory()
      ..selectedProvider = MarketProviderDescriptor(
        id: TwelveDataIntradayStockProvider.providerId,
        label: 'Twelve Data',
        dataset: 'US intraday',
        attribution: 'Twelve Data',
        requiresAuthorization: true,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IntradayMarketPanel(factory: factory)),
      ),
    );
    await tester.tap(find.text('開始更新'));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('twelve-data-quota-note')),
      findsOneWidget,
    );
  });

  testWidgets('privacy mode stops refresh and removes observed amounts', (
    tester,
  ) async {
    final factory = _Factory();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IntradayMarketPanel(factory: factory)),
      ),
    );
    await tester.tap(find.text('開始更新'));
    await tester.pump();
    await tester.pump();
    expect(find.text('最新價：1322.5'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntradayMarketPanel(factory: factory, showAmounts: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('1322.5'), findsNothing);
    expect(find.textContaining('隱私模式'), findsOneWidget);
    expect(find.text('開始更新'), findsNothing);
  });
}
