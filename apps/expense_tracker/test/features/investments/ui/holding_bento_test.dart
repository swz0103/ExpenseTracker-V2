/// Checks a holding's price chart: it reads the closes the exchanges gave
/// over the span picked, a finger on the line reads that day's close or,
/// on a buy, that buy and how it stands now, and without a connection or
/// closes it says so.
library;

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:expense_tracker/src/core/platform/sync_job.dart';
import 'package:expense_tracker/src/features/investments/ui/holding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

/// Closes from the exchanges: one a day, rising by one each day, from
/// [start]; [asked] keeps each span asked for.
final class _Prices extends SyncJob implements PriceHistory {
  _Prices(this.start, {this.empty = false}) : super('收盤價');

  final DateTime start;
  final bool empty;
  final asked = <DateTime>[];

  @override
  Future<void> refresh({bool force = false}) async {}

  @override
  Future<List<(DateTime, double)>> history(String code, DateTime from) async {
    asked.add(from);
    if (empty) return const [];
    return [
      for (var i = 0; i < 700; i++)
        (DateTime.utc(start.year, start.month, start.day + i), 500.0 + i),
    ];
  }
}

void main() {
  late Ledger ledger;
  setUp(() => ledger = demoLedger());

  Future<void> open(WidgetTester tester, {SyncJob? market}) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: HoldingPage(
            ledger: ledger,
            code: '2330',
            nav: Nav(
              open: (_) {},
              back: () {},
              compose: ({type = EntryType.expense, entry, draft}) async {},
              showEntry: (_) {},
              market: market,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The first buy of 2330 and when the closes begin, well before it.
  Entry firstBuy() => ledger.entryQueryService
      .tradesOf('2330')
      .where((e) => e.type == EntryType.buy)
      .reduce((a, b) => a.date.isBefore(b.date) ? a : b);

  testWidgets('everything since the first buy is shown first, with how far '
      'the price moved', (tester) async {
    final start = DateTime.utc(2025);
    final prices = _Prices(start);
    await open(tester, market: prices);
    final from = firstBuy().date;
    expect(prices.asked.single, from);
    expect(find.text('從第一次買到現在'), findsOneWidget);
    expect(find.bySemanticsLabel('走勢圖'), findsOneWidget);
    // From the close of the first buy's day to the last one given.
    final first = 500.0 + from.difference(start).inDays;
    const last = 500.0 + 699;
    final moved = ((last - first) * 100 / first).toStringAsFixed(1);
    expect(find.text('+$moved%'), findsOneWidget);
  });

  testWidgets('the last three months are asked for when picked', (
    tester,
  ) async {
    final prices = _Prices(DateTime.utc(2025));
    await open(tester, market: prices);
    await go(tester, ['3月']);
    expect(prices.asked.last, DateTime.utc(2026, 7, 4));
    expect(find.text('這段期間'), findsOneWidget);
  });

  testWidgets('a finger on the line reads the close of that day', (
    tester,
  ) async {
    await open(tester, market: _Prices(DateTime.utc(2025)));
    await go(tester, ['3月']);
    final closes = find.textContaining('收盤').evaluate().length;
    final chart = find.bySemanticsLabel('走勢圖');
    await tester.tapAt(tester.getTopLeft(chart) + const Offset(2, 100));
    await tester.pumpAndSettle();
    expect(find.textContaining('收盤').evaluate(), hasLength(closes + 1));
    expect(find.text('這段期間'), findsNothing);
  });

  testWidgets('over all of it, a finger on a buy reads that buy', (
    tester,
  ) async {
    final buy = firstBuy();
    final prices = _Prices(buy.date);
    await open(tester, market: prices);
    expect(prices.asked.last, buy.date);
    // The first close is the first buy's day: a finger anywhere up the
    // left edge, where its dot is, reads it.
    final chart = find.bySemanticsLabel('走勢圖');
    final corner = tester.getTopLeft(chart);
    for (var y = 0.0; y < 190; y += 20) {
      await tester.tapAt(corner + Offset(1, y));
      await tester.pumpAndSettle();
      if (find.textContaining('買 ').evaluate().isNotEmpty) break;
    }
    expect(find.textContaining('買 ${buy.shares} 股'), findsOneWidget);
    expect(find.textContaining('這批 '), findsOneWidget);
  });

  testWidgets('a month and a year are asked for as they are picked', (
    tester,
  ) async {
    final prices = _Prices(DateTime.utc(2025));
    await open(tester, market: prices);
    await go(tester, ['1月']);
    await go(tester, ['1年']);
    expect(prices.asked.skip(1), [
      DateTime.utc(2026, 9, 4),
      DateTime.utc(2025, 10, 4),
    ]);
  });

  testWidgets('a span with no closes says so', (tester) async {
    await open(tester, market: _Prices(DateTime.utc(2025), empty: true));
    expect(find.text('這段期間沒有收盤價'), findsOneWidget);
  });

  testWidgets('without the exchanges there is no line', (tester) async {
    await open(tester);
    expect(find.text('連上證交所、櫃買中心後才有走勢'), findsOneWidget);
  });

  group('R26: a span picked on a day later months lack starts on their '
      'last day', () {
    for (final (today, span, from) in [
      // 31 Mar 2027, a month back: February 2027 has 28 days.
      (DateTime.utc(2027, 3, 31), '1月', DateTime.utc(2027, 2, 28)),
      // 31 Dec 2026, three months back: September has 30 days.
      (DateTime.utc(2026, 12, 31), '3月', DateTime.utc(2026, 9, 30)),
      // 29 Feb 2028, a year back: February 2027 has 28 days.
      (DateTime.utc(2028, 2, 29), '1年', DateTime.utc(2027, 2, 28)),
    ]) {
      testWidgets('$span on $today', (tester) async {
        ledger = demoLedger(today: today);
        final prices = _Prices(DateTime.utc(2025));
        await open(tester, market: prices);
        await go(tester, [span]);
        expect(prices.asked.last, from);
      });
    }
  });
}
