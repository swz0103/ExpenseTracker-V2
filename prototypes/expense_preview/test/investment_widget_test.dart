import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/investment_market_services.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';
import 'package:market_adapters/market_adapters.dart';
import 'package:market_data/market_data.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, settle;

Future<void> _waitForKey(
  WidgetTester tester,
  String key, {
  int maxPolls = 160,
}) async {
  for (var i = 0; i < maxPolls; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) return;
  }
  throw StateError('$key did not appear');
}

Future<void> _waitForEnabledButton(WidgetTester tester, String key) async {
  for (var i = 0; i < 160; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    final finder = find.byKey(ValueKey(key));
    if (finder.evaluate().isEmpty) continue;
    final widget = tester.widget(finder);
    if (widget is FilledButton && widget.onPressed != null ||
        widget is TextButton && widget.onPressed != null) {
      return;
    }
  }
  throw StateError('$key did not become available');
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await settle(tester, maxPolls: 1200);
  await tester.pumpAndSettle();
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var i = 0; i < 12; i++) {
    final y = tester.getCenter(finder, warnIfMissed: false).dy;
    if (y >= 90 && y <= height - 20) break;
    await tester.drag(
      find.byType(ListView).first,
      Offset(0, y > height ? -350 : 350),
    );
    await settle(tester, maxPolls: 1200);
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _enterKey(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
}

Future<void> _openInvestmentScreen(
  WidgetTester tester,
  PreviewEngine engine, {
  InvestmentMarketServices? marketServices,
}) async {
  await tester.pumpWidget(
    PreviewApp(
      engine: Future.value(engine),
      documents: Documents(),
      investmentMarketServices: marketServices,
    ),
  );
  await settle(tester);
  await tester.enterText(find.byType(TextField).first, password);
  await tester.tap(find.byType(FilledButton).first);
  await settle(tester);
  await _tapKey(tester, 'open-investments');
  await _waitForKey(tester, 'investment-broker');
}

final class _MarketProvider
    implements StockCloseProvider, IntradayStockProvider {
  var closeCalls = 0;
  var intradayCalls = 0;

  @override
  MarketProviderDescriptor get descriptor => MarketProviderDescriptor(
    id: 'investment-screen-test-market',
    label: '整合測試行情',
    dataset: '整合測試資料集',
    attribution: '整合測試來源註記',
    requiresAuthorization: false,
  );

  @override
  bool supportsStockClose(InvestmentInstrument instrument) => true;

  @override
  Future<MarketResult<StockClose>> stockClose(
    InvestmentInstrument instrument, {
    BusinessDate? requiredAsOf,
  }) async {
    closeCalls++;
    return MarketResult(
      MarketState.available,
      value: StockClose(
        symbol: instrument.symbol,
        decimalPrice: '12',
        asOf: BusinessDate(2026, 9, 30),
        fetchedAt: UtcInstant(DateTime.utc(2026, 9, 30, 8)),
      ),
    );
  }

  @override
  bool supportsIntraday(
    InvestmentInstrument instrument,
    IntradayInterval interval,
  ) => true;

  @override
  Future<MarketResult<IntradayBar>> latestBar(
    InvestmentInstrument instrument, {
    required IntradayInterval interval,
  }) async {
    intradayCalls++;
    return MarketResult(
      MarketState.available,
      value: IntradayBar(
        symbol: instrument.symbol,
        interval: interval,
        startsAt: UtcInstant(DateTime.utc(2026, 9, 30, 8)),
        open: '11',
        high: '12',
        low: '10',
        close: '12',
        volume: BigInt.from(10),
        fetchedAt: UtcInstant(DateTime.utc(2026, 9, 30, 8, 1)),
      ),
    );
  }
}

Future<void> _prepareSyntheticBuy(WidgetTester tester) async {
  for (final (key, value) in [
    ('investment-broker', '合成券商'),
    ('investment-account', '合成投資帳戶'),
    ('investment-market', 'XNAS'),
    ('investment-symbol', 'TEST'),
    ('investment-name', '合成股票'),
    ('investment-date', '2026-09-29'),
    ('investment-quantity', '2'),
    ('investment-price', '10.25'),
    ('investment-gross', '20.50'),
    ('investment-fee', '0.50'),
    ('investment-tax', '0'),
  ]) {
    await _enterKey(tester, key, value);
  }
  await _tapKey(tester, 'review-investment-buy');
  expect(find.byKey(const ValueKey('investment-cash-preview')), findsOneWidget);
  expect(find.textContaining('21.00 TWD'), findsOneWidget);
  expect(find.byKey(const ValueKey('save-investment-buy')), findsOneWidget);
}

Future<InvestmentBuyPreview> _seedSyntheticBuy(PreviewEngine engine) async {
  final cash = account(engine, name: '合成現金');
  await engine.createAccount(cash, opening(cash));
  final broker = BrokerIdentity(
    id: PublicId.generate(),
    workspace: engine.workspace,
    name: '合成券商',
  );
  final investmentAccount = InvestmentAccount(
    id: PublicId.generate(),
    workspace: engine.workspace,
    brokerId: broker.id,
    fundingCashAccountId: cash.id,
    name: '合成投資帳戶',
    expectedVersion: 1,
  );
  final preview = InvestmentBuyPreview.create(
    id: PublicId.generate(),
    lotId: PublicId.generate(),
    operation: OperationKey(engine.workspace, OperationId(PublicId.generate())),
    tradedOn: BusinessDate(2026, 9, 29),
    broker: broker,
    account: investmentAccount,
    instrument: InvestmentInstrument(
      id: PublicId.generate(),
      kind: InstrumentKind.stock,
      marketCode: 'XNAS',
      symbol: 'TEST',
      name: '合成股票',
      tradingCurrency: cash.currency,
    ),
    funding: FundingCashAccount(
      id: cash.id,
      workspace: engine.workspace,
      currency: cash.currency,
      expectedVersion: cash.version,
    ),
    quantity: ShareQuantity.parse('2'),
    unitPrice: ShareUnitPrice.parse(cash.currency, '10.25'),
    executedGross: Money.parse(cash.currency, '20.50'),
    fee: Money.parse(cash.currency, '0.50'),
    tax: Money.parse(cash.currency, '0'),
  );
  await engine.submitInvestmentBuy(preview);
  return preview;
}

Future<void> _selectSyntheticHolding(WidgetTester tester) async {
  await _tapKey(tester, 'investment-sell-section');
  final dropdown = find.byKey(const ValueKey('investment-sell-position'));
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('XNAS:TEST').last);
  await _waitForKey(tester, 'investment-sell-holding');
}

Future<void> _prepareSyntheticSell(WidgetTester tester) async {
  for (final (key, value) in [
    ('investment-sell-date', '2026-09-30'),
    ('investment-sell-quantity', '1'),
    ('investment-sell-price', '15'),
    ('investment-sell-gross', '15'),
    ('investment-sell-fee', '0.50'),
    ('investment-sell-tax', '0'),
  ]) {
    await _enterKey(tester, key, value);
  }
  await _tapKey(tester, 'review-investment-sell');
  expect(
    find.byKey(const ValueKey('investment-sell-cash-preview')),
    findsOneWidget,
  );
  expect(find.textContaining('14.50 TWD'), findsOneWidget);
  expect(
    find.byKey(const ValueKey('investment-sell-result-preview')),
    findsOneWidget,
  );
  expect(find.byKey(const ValueKey('save-investment-sell')), findsOneWidget);
}

Future<void> _selectSyntheticDividend(WidgetTester tester) async {
  await _tapKey(tester, 'investment-dividend-position');
  await tester.pumpAndSettle();
  await tester.tap(
    find.byType(DropdownMenuItem<PublicId>).last,
    warnIfMissed: false,
  );
  await _waitForKey(tester, 'investment-dividend-gross');
}

Future<void> _prepareSyntheticDividend(WidgetTester tester) async {
  for (final (key, value) in [
    ('investment-dividend-date', '2026-09-30'),
    ('investment-dividend-gross', '10'),
    ('investment-dividend-tax', '1'),
    ('investment-dividend-fee', '0.25'),
    ('investment-dividend-net', '8.75'),
  ]) {
    await _enterKey(tester, key, value);
  }
  await _tapKey(tester, 'review-investment-dividend');
}

void main() {
  testWidgets('formal investment screen wires routed market tools on demand', (
    tester,
  ) async {
    final root = Directory('.dart_tool/investment-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('market-integration-');
    final engine = engineAt(
      work,
      MemoryVault(),
      schemaVersion: currentPreviewSchemaVersion,
    );
    final provider = _MarketProvider();
    final services = InvestmentMarketServices(
      gateway: MarketDataGateway(transport: const IoMarketTransport()),
      router: MarketDataRouter(MarketProviderRegistry([provider])),
    );
    try {
      await tester.runAsync(() async {
        await setup(engine);
        await _seedSyntheticBuy(engine);
        await engine.lock();
      });
      await _openInvestmentScreen(tester, engine, marketServices: services);
      expect(
        find.byKey(const ValueKey('investment-market-credentials-section')),
        findsNothing,
      );
      expect(provider.closeCalls, 0);
      expect(provider.intradayCalls, 0);

      await _tapKey(tester, 'refresh-investment-portfolio');
      await _waitForKey(tester, 'cross-currency-reporting-currency');
      expect(provider.closeCalls, 1);
      expect(find.textContaining('整合測試行情收盤價'), findsOneWidget);

      await _selectSyntheticHolding(tester);
      await _waitForKey(tester, 'investment-market-source-section');
      expect(provider.intradayCalls, 0);
      await _tapKey(tester, 'investment-market-source-section');
      expect(find.byKey(const ValueKey('intraday-toggle')), findsOneWidget);
      expect(provider.intradayCalls, 0);
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('buy needs second confirmation and hides uncommitted review', (
    tester,
  ) async {
    final root = Directory('.dart_tool/investment-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('confirm-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 21);
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final cash = account(engine, name: '合成現金');
        await engine.createAccount(cash, opening(cash));
        await engine.lock();
      });
      await _openInvestmentScreen(tester, engine);
      await _prepareSyntheticBuy(tester);
      expect((await tester.runAsync(engine.investmentBuys))!, isEmpty);
      expect(
        (await tester.runAsync(engine.accounts))!.single.balance.minorUnits,
        BigInt.from(10000),
      );

      // Privacy mode removes the confirmation surface and its stale preview.
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(find.byKey(const ValueKey('save-investment-buy')), findsNothing);
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();
      expect(find.byKey(const ValueKey('save-investment-buy')), findsNothing);

      await _waitForKey(tester, 'review-investment-buy', maxPolls: 1200);
      await _tapKey(tester, 'review-investment-buy');
      await _tapKey(tester, 'save-investment-buy');
      await _waitForKey(tester, 'investment-message', maxPolls: 1200);
      expect(find.textContaining('已記錄買入與銀行／現金扣款'), findsOneWidget);
      final facts = (await tester.runAsync(engine.investmentBuys))!;
      expect(facts, hasLength(1));
      expect(facts.single.preview.lot.quantity.toString(), '2');
      expect(facts.single.preview.lot.acquisitionCashCost.majorText, '21.00');
      expect(
        (await tester.runAsync(engine.accounts))!.single.balance.minorUnits,
        BigInt.from(7900),
      );
      expect(
        (await tester.runAsync(engine.entries))!
            .where((row) => row.kind == PostingKind.investmentBuy),
        hasLength(1),
      );
      await _waitForKey(tester, 'investment-buy-${facts.single.preview.id}');
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('ambiguous buy can be reconciled without a duplicate posting', (
    tester,
  ) async {
    final root = Directory('.dart_tool/investment-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('retry-');
    var interruptOnce = true;
    final engine = engineAt(
      work,
      MemoryVault(),
      schemaVersion: 21,
      draftCheckpoint: (stage) {
        if (stage == 'investment-buy-committed' && interruptOnce) {
          interruptOnce = false;
          throw StateError('synthetic interruption after commit');
        }
      },
    );
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final cash = account(engine, name: '合成現金');
        await engine.createAccount(cash, opening(cash));
        await engine.lock();
      });
      await _openInvestmentScreen(tester, engine);
      await _prepareSyntheticBuy(tester);
      await _tapKey(tester, 'save-investment-buy');
      await _waitForEnabledButton(tester, 'retry-investment-buy');
      expect((await tester.runAsync(engine.hasPendingInvestmentBuy))!, isTrue);
      expect((await tester.runAsync(engine.investmentBuys))!, hasLength(1));

      await _tapKey(tester, 'resolve-investment-buy');
      expect(find.text('核對並處理待確認買入？'), findsOneWidget);
      await tester.tap(find.text('開始核對'));
      await tester.pump();
      await _waitForEnabledButton(tester, 'review-investment-buy');
      expect((await tester.runAsync(engine.hasPendingInvestmentBuy))!, isFalse);
      expect((await tester.runAsync(engine.investmentBuys))!, hasLength(1));
      expect(
        (await tester.runAsync(engine.accounts))!.single.balance.minorUnits,
        BigInt.from(7900),
      );
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('sell previews lot cost and cash before explicit confirmation', (
    tester,
  ) async {
    final root = Directory('.dart_tool/investment-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('sell-confirm-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 22);
    try {
      late InvestmentBuyPreview buy;
      await tester.runAsync(() async {
        await setup(engine);
        buy = await _seedSyntheticBuy(engine);
        await engine.lock();
      });
      await _openInvestmentScreen(tester, engine);
      await _selectSyntheticHolding(tester);
      await _prepareSyntheticSell(tester);
      expect(
        (await tester.runAsync(engine.accounts))!.single.balance.minorUnits,
        BigInt.from(7900),
      );
      expect(
        (await tester.runAsync(
          () => engine.investmentHoldingLots(buy.account.id, buy.instrument.id),
        ))!.single.remainingQuantity.toString(),
        '2',
      );

      // Hiding the screen invalidates the reviewed lot snapshot.
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(find.byKey(const ValueKey('save-investment-sell')), findsNothing);
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await _waitForKey(tester, 'investment-sell-section');
      await _tapKey(tester, 'investment-sell-section');
      await _waitForKey(tester, 'investment-sell-holding');
      expect(find.byKey(const ValueKey('save-investment-sell')), findsNothing);

      await _tapKey(tester, 'review-investment-sell');
      await _tapKey(tester, 'save-investment-sell');
      await _waitForEnabledButton(tester, 'review-investment-sell');
      final lots = (await tester.runAsync(
        () => engine.investmentHoldingLots(buy.account.id, buy.instrument.id),
      ))!;
      expect(lots, hasLength(1));
      expect(lots.single.remainingQuantity.toString(), '1');
      expect(lots.single.remainingCost.majorText, '10.50');
      expect(
        (await tester.runAsync(engine.accounts))!.single.balance.minorUnits,
        BigInt.from(9350),
      );
      expect(
        (await tester.runAsync(
          () => engine.investmentSales(buy.account.id, buy.instrument.id),
        ))!,
        hasLength(1),
      );
      await _waitForKey(tester, 'investment-factual-return');
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('investment-factual-return')),
            )
            .data,
        contains('已實現損益 4.00 TWD'),
      );
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('ambiguous sell retries the same lot and one cash credit', (
    tester,
  ) async {
    final root = Directory('.dart_tool/investment-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('sell-retry-');
    var interruptOnce = true;
    final engine = engineAt(
      work,
      MemoryVault(),
      schemaVersion: 22,
      draftCheckpoint: (stage) {
        if (stage == 'investment-sell-committed' && interruptOnce) {
          interruptOnce = false;
          throw StateError('synthetic interruption after sale commit');
        }
      },
    );
    try {
      late InvestmentBuyPreview buy;
      await tester.runAsync(() async {
        await setup(engine);
        buy = await _seedSyntheticBuy(engine);
        await engine.lock();
      });
      await _openInvestmentScreen(tester, engine);
      await _selectSyntheticHolding(tester);
      await _prepareSyntheticSell(tester);
      await _tapKey(tester, 'save-investment-sell');
      await _waitForEnabledButton(tester, 'retry-investment-sell');
      expect((await tester.runAsync(engine.hasPendingInvestmentSell))!, isTrue);
      expect(
        (await tester.runAsync(
          () => engine.investmentSales(buy.account.id, buy.instrument.id),
        ))!,
        hasLength(1),
      );
      await _tapKey(tester, 'retry-investment-sell');
      await _waitForEnabledButton(tester, 'review-investment-sell');
      expect(
        (await tester.runAsync(engine.hasPendingInvestmentSell))!,
        isFalse,
      );
      expect(
        (await tester.runAsync(
          () => engine.investmentSales(buy.account.id, buy.instrument.id),
        ))!,
        hasLength(1),
      );
      expect(
        (await tester.runAsync(engine.accounts))!.single.balance.minorUnits,
        BigInt.from(9350),
      );
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('dividend previews net cash before saving one investment fact', (
    tester,
  ) async {
    final root = Directory('.dart_tool/investment-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('dividend-confirm-');
    final engine = engineAt(
      work,
      MemoryVault(),
      schemaVersion: currentPreviewSchemaVersion,
    );
    try {
      await tester.runAsync(() async {
        await setup(engine);
        await _seedSyntheticBuy(engine);
        await engine.lock();
      });
      await _openInvestmentScreen(tester, engine);
      await _tapKey(tester, 'investment-dividend-section');
      await _selectSyntheticDividend(tester);
      await _prepareSyntheticDividend(tester);
      expect(
        find.byKey(const ValueKey('investment-dividend-cash-preview')),
        findsOneWidget,
      );
      expect(find.textContaining('8.75 TWD'), findsOneWidget);
      expect((await tester.runAsync(engine.investmentDividends))!, isEmpty);
      expect(
        (await tester.runAsync(engine.accounts))!.single.balance.minorUnits,
        BigInt.from(7900),
      );

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('save-investment-dividend')),
        findsNothing,
      );
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await _waitForKey(tester, 'investment-dividend-section');
      await _tapKey(tester, 'investment-dividend-section');
      expect(
        find.byKey(const ValueKey('save-investment-dividend')),
        findsNothing,
      );

      await _selectSyntheticDividend(tester);
      await _prepareSyntheticDividend(tester);
      await _tapKey(tester, 'save-investment-dividend');
      await _waitForEnabledButton(tester, 'review-investment-dividend');
      final facts = (await tester.runAsync(engine.investmentDividends))!;
      expect(facts, hasLength(1));
      expect(facts.single.preview.netCashCredit.majorText, '8.75');
      final activity = (await tester.runAsync(
        () => engine.activity(facts.single.eventId),
      ))!;
      expect(activity, hasLength(1));
      expect(activity.single.entry.kind, PostingKind.investmentDividend);
      expect(
        (await tester.runAsync(engine.accounts))!.single.balance.minorUnits,
        BigInt.from(8775),
      );
      await _waitForKey(
        tester,
        'investment-dividend-${facts.single.preview.id.value}',
      );
      await _selectSyntheticHolding(tester);
      await _waitForKey(tester, 'investment-factual-return');
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('investment-factual-return')),
            )
            .data,
        contains('現金股息淨額 8.75'),
      );
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('split previews unchanged cost and needs explicit confirmation', (
    tester,
  ) async {
    final root = Directory('.dart_tool/investment-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('split-confirm-');
    final engine = engineAt(
      work,
      MemoryVault(),
      schemaVersion: currentPreviewSchemaVersion,
    );
    try {
      late InvestmentBuyPreview buy;
      await tester.runAsync(() async {
        await setup(engine);
        buy = await _seedSyntheticBuy(engine);
        await engine.lock();
      });
      await _openInvestmentScreen(tester, engine);
      await _tapKey(tester, 'investment-split-section');
      await _tapKey(tester, 'investment-split-position');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(DropdownMenuItem<PublicId>).last,
        warnIfMissed: false,
      );
      await _waitForKey(tester, 'investment-split-new');
      await _enterKey(tester, 'investment-split-date', '2026-10-01');
      await _enterKey(tester, 'investment-split-new', '2');
      await _enterKey(tester, 'investment-split-old', '1');
      await _tapKey(tester, 'review-investment-split');
      expect(
        find.byKey(const ValueKey('save-investment-split')),
        findsOneWidget,
      );
      expect(find.textContaining('21.00 TWD'), findsWidgets);
      expect((await tester.runAsync(engine.investmentSplits))!, isEmpty);
      expect(
        (await tester.runAsync(engine.accounts))!.single.balance.minorUnits,
        BigInt.from(7900),
      );
      await _tapKey(tester, 'save-investment-split');
      await _waitForEnabledButton(tester, 'review-investment-split');
      expect((await tester.runAsync(engine.investmentSplits))!, hasLength(1));
      expect(
        (await tester.runAsync(
          () => engine.investmentHoldingLots(buy.account.id, buy.instrument.id),
        ))!.single.remainingQuantity.toString(),
        '4',
      );
      expect(
        (await tester.runAsync(engine.accounts))!.single.balance.minorUnits,
        BigInt.from(7900),
      );
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('ambiguous split result offers same-action retry', (
    tester,
  ) async {
    final root = Directory('.dart_tool/investment-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('split-retry-');
    var interruptOnce = true;
    final engine = engineAt(
      work,
      MemoryVault(),
      schemaVersion: currentPreviewSchemaVersion,
      draftCheckpoint: (stage) {
        if (stage == 'investment-split-committed' && interruptOnce) {
          interruptOnce = false;
          throw StateError('synthetic acknowledgement loss');
        }
      },
    );
    try {
      await tester.runAsync(() async {
        await setup(engine);
        await _seedSyntheticBuy(engine);
        await engine.lock();
      });
      await _openInvestmentScreen(tester, engine);
      await _tapKey(tester, 'investment-split-section');
      await _tapKey(tester, 'investment-split-position');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(DropdownMenuItem<PublicId>).last,
        warnIfMissed: false,
      );
      await _waitForKey(tester, 'investment-split-new');
      await _enterKey(tester, 'investment-split-date', '2026-10-01');
      await _enterKey(tester, 'investment-split-new', '2');
      await _enterKey(tester, 'investment-split-old', '1');
      await _tapKey(tester, 'review-investment-split');
      await _tapKey(tester, 'save-investment-split');
      await _waitForEnabledButton(tester, 'retry-investment-split');
      expect(
        (await tester.runAsync(engine.hasPendingInvestmentSplit))!,
        isTrue,
      );
      expect((await tester.runAsync(engine.investmentSplits))!, hasLength(1));
      await _tapKey(tester, 'retry-investment-split');
      await _waitForEnabledButton(tester, 'review-investment-split');
      expect(
        (await tester.runAsync(engine.hasPendingInvestmentSplit))!,
        isFalse,
      );
      expect((await tester.runAsync(engine.investmentSplits))!, hasLength(1));
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });
}
