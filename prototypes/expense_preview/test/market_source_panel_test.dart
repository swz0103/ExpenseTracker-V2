import 'package:expense_preview/market_source_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_data/market_data.dart';

void main() {
  testWidgets('automatic fallback shows actual source and every attempt', (
    tester,
  ) async {
    final controller = _Controller();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarketSourcePanel(controller: controller)),
      ),
    );
    await tester.tap(find.text('查詢參考資料'));
    await tester.pumpAndSettle();
    expect(controller.lastFixedProvider, isNull);
    expect(find.text('實際來源：備援來源'), findsOneWidget);
    expect(find.text('資料集：backup-dataset'), findsOneWidget);
    expect(find.text('來源註記：backup attribution'), findsOneWidget);
    expect(find.text('已使用備援來源；嘗試紀錄：'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('market-attempt-primary')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('market-attempt-backup')), findsOneWidget);
  });

  testWidgets('fixed provider selection is passed without silent fallback', (
    tester,
  ) async {
    final controller = _Controller();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarketSourcePanel(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('market-provider-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主要來源').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('查詢參考資料'));
    await tester.pumpAndSettle();
    expect(controller.lastFixedProvider, 'primary');
  });

  testWidgets(
    'cross-check displays values side by side and refuses averaging',
    (tester) async {
      final controller = _Controller();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MarketSourcePanel(controller: controller)),
        ),
      );
      await tester.tap(find.text('核對所有可用來源'));
      await tester.pumpAndSettle();
      expect(find.text('來源資料有衝突，不自動選值或平均。'), findsOneWidget);
      expect(find.text('100.00'), findsOneWidget);
      expect(find.text('101.00'), findsOneWidget);
      expect(find.text('市場資料只供估值參考，不會改寫成交、成本、換匯或現金。'), findsOneWidget);
    },
  );

  testWidgets('privacy mode clears and blocks reference values', (
    tester,
  ) async {
    final controller = _Controller();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarketSourcePanel(controller: controller)),
      ),
    );
    await tester.tap(find.text('查詢參考資料'));
    await tester.pumpAndSettle();
    expect(find.text('參考值：101.00'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarketSourcePanel(controller: controller, showAmounts: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('101.00'), findsNothing);
    expect(find.textContaining('隱私模式'), findsOneWidget);
    expect(find.text('查詢參考資料'), findsNothing);
  });
}

MarketProviderDescriptor _provider(String id, String label) =>
    MarketProviderDescriptor(
      id: id,
      label: label,
      dataset: id == 'primary' ? 'primary-dataset' : 'backup-dataset',
      attribution: id == 'primary'
          ? 'primary attribution'
          : 'backup attribution',
      requiresAuthorization: false,
    );

final class _Controller implements MarketSourcePanelController {
  String? lastFixedProvider;

  @override
  List<MarketProviderDescriptor> get providers => [
    _provider('primary', '主要來源'),
    _provider('backup', '備援來源'),
  ];

  @override
  Future<MarketSourceResultView> fetch({String? fixedProviderId}) async {
    lastFixedProvider = fixedProviderId;
    final selected = fixedProviderId == 'primary'
        ? _provider('primary', '主要來源')
        : _provider('backup', '備援來源');
    return MarketSourceResultView(
      state: MarketState.available,
      valueText: '101.00',
      observationText: '2026-09-30',
      provider: selected,
      attempts: fixedProviderId == 'primary'
          ? [
              MarketProviderAttempt(
                provider: selected,
                state: MarketState.available,
                reason: null,
              ),
            ]
          : [
              MarketProviderAttempt(
                provider: _provider('primary', '主要來源'),
                state: MarketState.failed,
                reason: '暫時無法連線',
              ),
              MarketProviderAttempt(
                provider: selected,
                state: MarketState.available,
                reason: null,
              ),
            ],
    );
  }

  @override
  Future<MarketCrossCheckView> crossCheck() async => MarketCrossCheckView(
    conflict: true,
    reason: '觀測值不同',
    rows: [
      MarketCrossCheckRowView(
        provider: _provider('primary', '主要來源'),
        state: MarketState.available,
        valueText: '100.00',
        observationText: '2026-09-30',
      ),
      MarketCrossCheckRowView(
        provider: _provider('backup', '備援來源'),
        state: MarketState.available,
        valueText: '101.00',
        observationText: '2026-09-30',
      ),
    ],
  );
}
