import 'dart:async';

import 'package:expense_preview/historical_fx_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_data/market_data.dart';

const _exact = '''KEY,FREQ,CURRENCY,CURRENCY_DENOM,EXR_TYPE,EXR_SUFFIX,TIME_PERIOD,OBS_VALUE
EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2026-09-29,1.12345
''';

final class _Transport implements MarketTransport {
  _Transport(this.handle);
  final Future<MarketResponse> Function(Uri) handle;
  final requests = <Uri>[];

  @override
  Future<MarketResponse> get(Uri uri) {
    requests.add(uri);
    return handle(uri);
  }
}

void main() {
  Future<void> show(
    WidgetTester tester,
    MarketDataGateway gateway, {
    bool visible = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HistoricalFxPanel(showAmounts: visible, gateway: gateway),
      ),
    ),
  );

  Future<void> request(WidgetTester tester, String date) async {
    await tester.enterText(
      find.byKey(const ValueKey('historical-fx-date')),
      date,
    );
    await tester.tap(find.byKey(const ValueKey('request-historical-fx')));
    await tester.pumpAndSettle();
  }

  testWidgets('explicit historical lookup shows exact date and source', (
    tester,
  ) async {
    final transport = _Transport(
      (_) async => const MarketResponse(200, _exact),
    );
    final gateway = MarketDataGateway(
      transport: transport,
      clock: () => DateTime.utc(2026, 9, 30),
    );
    await show(tester, gateway);
    expect(transport.requests, isEmpty);
    await request(tester, '2026-09-29');
    expect(transport.requests, hasLength(1));
    expect(
      transport.requests.single.queryParameters['startPeriod'],
      '2026-09-22',
    );
    expect(
      transport.requests.single.queryParameters['endPeriod'],
      '2026-09-29',
    );
    expect(find.textContaining('歐洲央行 · 觀測日 2026-09-29'), findsOneWidget);
    expect(find.textContaining('1 EUR ≈ 1.123450 USD'), findsOneWidget);
    expect(find.textContaining('實際換匯與入帳以銀行或券商'), findsOneWidget);
  });

  testWidgets(
    'earlier observation is disclosed and never shown as dated rate',
    (tester) async {
      final transport = _Transport(
        (_) async => const MarketResponse(200, _exact),
      );
      await show(
        tester,
        MarketDataGateway(
          transport: transport,
          clock: () => DateTime.utc(2026, 9, 30),
        ),
      );
      await request(tester, '2026-09-30');
      expect(find.textContaining('觀測日 2026-09-29'), findsOneWidget);
      expect(find.byKey(const ValueKey('historical-fx-stale')), findsOneWidget);
      expect(find.textContaining('較早參考值：1 EUR ≈ 1.123450 USD'), findsOneWidget);
      expect(find.byKey(const ValueKey('historical-fx-value')), findsNothing);
    },
  );

  testWidgets('invalid date does not contact provider', (tester) async {
    final transport = _Transport(
      (_) async => const MarketResponse(200, _exact),
    );
    await show(tester, MarketDataGateway(transport: transport));
    await request(tester, '2026-02-30');
    expect(transport.requests, isEmpty);
    expect(find.textContaining('請輸入有效日期'), findsOneWidget);
  });

  testWidgets('privacy hides a prior rate and ignores a late lookup', (
    tester,
  ) async {
    final pending = Completer<MarketResponse>();
    final transport = _Transport((_) => pending.future);
    final gateway = MarketDataGateway(
      transport: transport,
      clock: () => DateTime.utc(2026, 9, 30),
    );
    await show(tester, gateway);
    await tester.enterText(
      find.byKey(const ValueKey('historical-fx-date')),
      '2026-09-29',
    );
    await tester.tap(find.byKey(const ValueKey('request-historical-fx')));
    await tester.pump();
    await show(tester, gateway, visible: false);
    pending.complete(const MarketResponse(200, _exact));
    await tester.pumpAndSettle();
    await show(tester, gateway);
    expect(find.byKey(const ValueKey('historical-fx-value')), findsNothing);
    expect(find.textContaining('1.123450'), findsNothing);
  });
}
