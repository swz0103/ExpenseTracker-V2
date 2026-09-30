import 'dart:async';

import 'package:expense_preview/investment_portfolio_summary_panel.dart';
import 'package:expense_preview/privacy_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:market_data/market_data.dart';

final class _Transport implements MarketTransport {
  _Transport(this.status, this.body);
  final int status;
  final String body;
  int calls = 0;

  @override
  Future<MarketResponse> get(Uri uri) async {
    calls++;
    return MarketResponse(status, body);
  }
}

final class _Source implements InvestmentPortfolioSource {
  final facts = <InvestmentBuyFact>[];
  final lots = <(PublicId, PublicId), List<InvestmentHoldingLot>>{};
  bool unlocked = true;
  bool failLots = false;
  Completer<List<InvestmentBuyFact>>? pendingBuys;
  int lotReads = 0;

  @override
  bool get isUnlocked => unlocked;
  @override
  bool get supportsSales => true;
  @override
  bool get supportsDividends => true;
  @override
  bool get supportsSplits => true;
  @override
  Future<List<InvestmentBuyFact>> buys() async =>
      pendingBuys == null ? facts : pendingBuys!.future;
  @override
  Future<List<InvestmentHoldingLot>> openLots(
    PublicId account,
    PublicId instrument,
  ) async {
    lotReads++;
    if (failLots) throw StateError('Synthetic read failure');
    return lots[(account, instrument)] ?? [];
  }

  @override
  Future<List<InvestmentSellFact>> sales(
    PublicId account,
    PublicId instrument,
  ) async => [];
  @override
  Future<List<InvestmentDividendFact>> dividends(PublicId account) async => [];
  @override
  Future<List<InvestmentSplitFact>> splits(PublicId account) async => [];
}

void _addPosition(
  _Source source, {
  required Currency currency,
  required String market,
  required String symbol,
}) {
  final workspace = WorkspaceId(PublicId.generate());
  final broker = BrokerIdentity(
    id: PublicId.generate(),
    workspace: workspace,
    name: '測試券商',
  );
  final fundingId = PublicId.generate();
  final account = InvestmentAccount(
    id: PublicId.generate(),
    workspace: workspace,
    brokerId: broker.id,
    fundingCashAccountId: fundingId,
    name: '測試投資帳戶',
    expectedVersion: 1,
  );
  final instrument = InvestmentInstrument(
    id: PublicId.generate(),
    kind: InstrumentKind.stock,
    marketCode: market,
    symbol: symbol,
    name: '合成股票',
    tradingCurrency: currency,
  );
  final preview = InvestmentBuyPreview.create(
    id: PublicId.generate(),
    lotId: PublicId.generate(),
    operation: OperationKey(workspace, OperationId(PublicId.generate())),
    tradedOn: BusinessDate(2026, 9, 29),
    broker: broker,
    account: account,
    instrument: instrument,
    funding: FundingCashAccount(
      id: fundingId,
      workspace: workspace,
      currency: currency,
      expectedVersion: 1,
    ),
    quantity: ShareQuantity.parse('2'),
    unitPrice: ShareUnitPrice.parse(currency, '10'),
    executedGross: Money.parse(currency, '20'),
    fee: Money.parse(currency, '0'),
    tax: Money.parse(currency, '0'),
  );
  source.facts.add(InvestmentBuyFact(preview, PublicId.generate()));
  source.lots[(account.id, instrument.id)] = [
    InvestmentHoldingLot(
      id: preview.lot.id,
      investmentAccountId: account.id,
      instrumentId: instrument.id,
      acquiredOn: preview.tradedOn,
      remainingQuantity: preview.quantity,
      remainingCost: Money.parse(currency, '20'),
      expectedVersion: 1,
    ),
  ];
}

const _twseRows = '''[
  {"Date":"1150929","Code":"2330","Name":"測試上市股","ClosingPrice":"15.00"}
]''';

void main() {
  final twd = Currency('TWD', 2);
  final usd = Currency('USD', 2);

  MarketDataGateway gateway(_Transport transport) => MarketDataGateway(
    transport: transport,
    clock: () => DateTime.utc(2026, 9, 30, 4),
  );

  Future<void> show(
    WidgetTester tester,
    _Source source,
    MarketDataGateway quotes, {
    PrivacyMode privacy = PrivacyMode.visible,
    int revision = 0,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InvestmentPortfolioSummaryPanel(
          source: source,
          gateway: quotes,
          privacy: privacy,
          revision: revision,
        ),
      ),
    ),
  );

  Future<void> refresh(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('refresh-investment-portfolio')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('committed lots and sourced close produce one TWD summary', (
    tester,
  ) async {
    final source = _Source();
    _addPosition(source, currency: twd, market: 'TWSE', symbol: '2330');
    final transport = _Transport(200, _twseRows);
    await show(tester, source, gateway(transport));
    expect(transport.calls, 0);
    await refresh(tester);
    expect(transport.calls, 1);
    expect(
      find.byKey(const ValueKey('investment-portfolio-TWD')),
      findsOneWidget,
    );
    expect(find.textContaining('剩餘成本 TWD 20.00'), findsOneWidget);
    expect(find.textContaining('參考市值 TWD 30.00'), findsOneWidget);
    expect(find.textContaining('未實現 TWD 10.00'), findsOneWidget);
    expect(find.textContaining('交易日 2026-09-29'), findsOneWidget);
  });

  testWidgets(
    'separate currency remains incomplete when its market is unsupported',
    (tester) async {
      final source = _Source();
      _addPosition(source, currency: twd, market: 'TWSE', symbol: '2330');
      _addPosition(source, currency: usd, market: 'XNAS', symbol: 'TEST');
      await show(tester, source, gateway(_Transport(200, _twseRows)));
      await refresh(tester);
      expect(
        find.byKey(const ValueKey('investment-portfolio-TWD')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('investment-portfolio-USD')),
        findsOneWidget,
      );
      expect(find.textContaining('剩餘成本 USD 20.00'), findsOneWidget);
      expect(find.textContaining('估值不完整：1 個開放持倉'), findsOneWidget);
      expect(find.textContaining('此市場無支援來源'), findsOneWidget);
      expect(find.textContaining('參考市值 USD'), findsNothing);
    },
  );

  testWidgets('failed quote never becomes a zero market value', (tester) async {
    final source = _Source();
    _addPosition(source, currency: twd, market: 'TWSE', symbol: '2330');
    await show(tester, source, gateway(_Transport(503, 'unavailable')));
    await refresh(tester);
    expect(find.textContaining('剩餘成本 TWD 20.00'), findsOneWidget);
    expect(find.textContaining('估值不完整'), findsOneWidget);
    expect(find.textContaining('參考市值'), findsNothing);
  });

  testWidgets('failed authoritative read clears earlier totals', (
    tester,
  ) async {
    final source = _Source();
    _addPosition(source, currency: twd, market: 'TWSE', symbol: '2330');
    await show(tester, source, gateway(_Transport(200, _twseRows)));
    await refresh(tester);
    expect(find.textContaining('參考市值 TWD 30.00'), findsOneWidget);
    source.failLots = true;
    await refresh(tester);
    expect(
      find.byKey(const ValueKey('investment-portfolio-unavailable')),
      findsOneWidget,
    );
    expect(find.textContaining('TWSE:2330 的已提交紀錄或權威持倉讀取失敗'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('investment-portfolio-TWD')),
      findsNothing,
    );
  });

  testWidgets('over 20 positions shows no partial totals or reads', (
    tester,
  ) async {
    final source = _Source();
    for (var index = 0; index < 21; index++) {
      _addPosition(source, currency: usd, market: 'XNAS', symbol: 'TEST$index');
    }
    await show(tester, source, gateway(_Transport(200, _twseRows)));
    await refresh(tester);
    expect(
      find.byKey(const ValueKey('investment-portfolio-unavailable')),
      findsOneWidget,
    );
    expect(source.lotReads, 0);
    expect(
      find.byKey(const ValueKey('investment-portfolio-USD')),
      findsNothing,
    );
  });

  testWidgets('privacy switch cancels a pending read and clears disclosure', (
    tester,
  ) async {
    final source = _Source();
    _addPosition(source, currency: twd, market: 'TWSE', symbol: '2330');
    final quotes = gateway(_Transport(200, _twseRows));
    await show(tester, source, quotes);
    await refresh(tester);
    expect(find.textContaining('參考市值 TWD 30.00'), findsOneWidget);
    source.pendingBuys = Completer<List<InvestmentBuyFact>>();
    await tester.tap(
      find.byKey(const ValueKey('refresh-investment-portfolio')),
    );
    await tester.pump();
    await show(tester, source, quotes, privacy: PrivacyMode.hidden);
    expect(find.textContaining('20.00'), findsNothing);
    expect(find.textContaining('30.00'), findsNothing);
    source.pendingBuys!.complete(source.facts);
    await tester.pumpAndSettle();
    await show(tester, source, quotes);
    expect(find.textContaining('參考市值'), findsNothing);
  });
}
