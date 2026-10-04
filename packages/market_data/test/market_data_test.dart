import 'dart:async';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';
import 'package:test/test.dart';

const twseRows = '''[
  {"Date":"1150929","Code":"2330","Name":"台積電","ClosingPrice":"1,234.50"},
  {"Date":"1150929","Code":"0050","Name":"元大台灣50","ClosingPrice":"62.75"},
  {"Date":"1150929","Code":"2317","Name":"鴻海","ClosingPrice":"--"}
]''';

const tpexRows = '''[
  {"Date":"1150929","SecuritiesCompanyCode":"6488","Close":"410.50"},
  {"Date":"1150929","SecuritiesCompanyCode":"00679B","Close":"28.10"}
]''';

/// The shape of Bank of Taiwan's board: buy side, then sell side, each
/// with cash, spot and seven forward columns.
String board(List<String> rows) {
  final days = [10, 30, 60, 90, 120, 150, 180];
  final side = ['匯率', '現金', '即期', for (final d in days) '遠期$d天'];
  final header = ['\uFEFF幣別', ...side, ...side].join(',');
  return [header, ...rows].join('\r\n');
}

String boardRow(String code, String cashBuy, String spotBuy, String spotSell) {
  final forwards = List.filled(7, '0.00000').join(',');
  final buy = ['本行買入', cashBuy, spotBuy, forwards];
  final sell = ['本行賣出', '32.15500', spotSell, forwards];
  return [code, ...buy, ...sell].join(',');
}

final class FakeTransport implements MarketTransport {
  FakeTransport(this.handle);

  final Future<MarketResponse> Function(Uri) handle;
  final requests = <Uri>[];

  @override
  Future<MarketResponse> get(Uri uri) {
    requests.add(uri);
    return handle(uri);
  }
}

InvestmentInstrument instrument(
  String symbol, {
  InstrumentKind kind = InstrumentKind.stock,
  String market = 'TWSE',
}) => InvestmentInstrument(
  id: PublicId.generate(),
  kind: kind,
  marketCode: market,
  symbol: symbol,
  name: symbol,
  tradingCurrency: Currency.of('TWD'),
);

void main() {
  late DateTime now;
  setUp(() => now = DateTime.utc(2026, 9, 30, 4));

  MarketDataGateway gateway(FakeTransport transport) =>
      MarketDataGateway(transport: transport, clock: () => now);

  test('TWSE and TPEx closes are exact and share one snapshot each', () async {
    String rows(Uri uri) =>
        uri == MarketDataGateway.twseUri ? twseRows : tpexRows;
    final transport = FakeTransport(
      (uri) async => MarketResponse(200, rows(uri)),
    );
    final market = gateway(transport);
    final tsmc = await market.stockClose(instrument('2330'));
    final etf = await market.stockClose(
      instrument('0050', kind: InstrumentKind.etf),
    );
    final otc = await market.stockClose(instrument('6488', market: 'TPEX'));
    final bond = await market.stockClose(
      instrument('00679B', kind: InstrumentKind.etf, market: 'TPEX'),
    );
    expect(tsmc.state, MarketState.available);
    expect(tsmc.value!.decimalPrice, '1234.50');
    expect(tsmc.value!.asOf, BusinessDate(2026, 9, 29));
    expect(tsmc.value!.fetchedAt.value, now);
    expect(etf.value!.decimalPrice, '62.75');
    expect(otc.value!.decimalPrice, '410.50');
    expect(bond.value!.decimalPrice, '28.10');
    expect(transport.requests, [
      MarketDataGateway.twseUri,
      MarketDataGateway.tpexUri,
    ]);
  });

  test('no trade, not listed and unsupported are told apart', () async {
    final market = gateway(
      FakeTransport((_) async => const MarketResponse(200, twseRows)),
    );
    expect(
      (await market.stockClose(instrument('2317'))).state,
      MarketState.missing,
    );
    expect(
      (await market.stockClose(instrument('9999'))).state,
      MarketState.missing,
    );
    for (final odd in [
      instrument('AAPL', market: 'XNAS'),
      instrument('12345'),
      instrument('0050'),
    ]) {
      expect(
        (await market.stockClose(odd)).state,
        MarketState.unsupported,
        reason: odd.symbol,
      );
    }
  });

  test('an old close is stale; a failed refresh keeps the last one', () async {
    var fail = false;
    final transport = FakeTransport(
      (_) async => fail
          ? const MarketResponse(503, '')
          : const MarketResponse(200, twseRows),
    );
    final market = gateway(transport);
    expect(
      (await market.stockClose(instrument('2330'))).state,
      MarketState.available,
    );

    // Within the cache time no new request is made.
    now = now.add(const Duration(minutes: 10));
    await market.stockClose(instrument('2330'));
    expect(transport.requests, hasLength(1));

    // Days later the refresh fails: the last close is kept, marked stale,
    // and the next attempt waits a minute.
    now = now.add(const Duration(days: 5));
    fail = true;
    final kept = await market.stockClose(instrument('2330'));
    expect(kept.state, MarketState.stale);
    expect(kept.value!.decimalPrice, '1234.50');
    await market.stockClose(instrument('2330'));
    expect(transport.requests, hasLength(2));

    // Once the provider answers again, the snapshot's date decides.
    fail = false;
    now = now.add(const Duration(minutes: 2));
    final old = await market.stockClose(instrument('2330'));
    expect(old.state, MarketState.stale);
    expect(transport.requests, hasLength(3));
  });

  test('concurrent lookups share one request', () async {
    final release = Completer<void>();
    final transport = FakeTransport((_) async {
      await release.future;
      return const MarketResponse(200, twseRows);
    });
    final market = gateway(transport);
    final both = Future.wait([
      market.stockClose(instrument('2330')),
      market.stockClose(instrument('0050', kind: InstrumentKind.etf)),
    ]);
    release.complete();
    final states = [for (final result in await both) result.state];
    expect(states, everyElement(MarketState.available));
    expect(transport.requests, hasLength(1));
  });

  test('a bad snapshot or a duplicated symbol fails closed', () async {
    for (final body in [
      '{"not":"a list"}',
      '[{"Date":"115","Code":"2330","ClosingPrice":"1"}]',
      '[{"Date":"1150929","Code":"2330","ClosingPrice":"1e3"}]',
      '[{"Date":"1150929","Code":"2330","ClosingPrice":"1"},'
          '{"Date":"1150929","Code":"2330","ClosingPrice":"2"}]',
    ]) {
      final market = gateway(
        FakeTransport((_) async => MarketResponse(200, body)),
      );
      expect(
        (await market.stockClose(instrument('2330'))).state,
        MarketState.failed,
        reason: body,
      );
    }
  });

  test('the bank board gives exact rates for the currencies used', () async {
    now = DateTime.utc(2026, 9, 30, 17); // 01:00 on 1 October in Taipei.
    final transport = FakeTransport(
      (_) async => MarketResponse(
        200,
        board([
          boardRow('USD', '31.48500', '31.83500', '31.98500'),
          boardRow('JPY', '0.20570', '0.21250', '0.21750'),
          boardRow('THB', '0.00000', '0.95870', '1.00870'),
          boardRow('ZAR', '0.00000', '1.77000', '1.85000'),
        ]),
      ),
    );
    final result = await gateway(transport).bankRates();
    expect(result.state, MarketState.available);
    final rates = result.value!;
    expect(rates.asOf, BusinessDate(2026, 10, 1));
    final usd = rates[Currency.of('USD')]!;
    final hundred = Money(Currency.of('USD'), BigInt.from(10000));
    // Valued at the spot buying rate; whole NT$, rounded half up.
    expect(usd.valuation!.convert(hundred).minorUnits, BigInt.from(3184));
    expect(usd.spotSell!.convert(hundred).minorUnits, BigInt.from(3199));
    expect(rates[Currency.of('THB')]!.cashBuy, isNull);
    expect(rates[Currency.of('THB')]!.valuation, isNotNull);
    // A currency this app does not use is skipped.
    expect(rates.rates.keys, {'USD', 'JPY', 'THB'});
  });

  test('a page that is not the board, or fails, is refused', () async {
    for (final response in [
      const MarketResponse(200, '<html>maintenance</html>'),
      MarketResponse(200, board(['USD,本行買入,31.4,31.8'])),
      const MarketResponse(500, ''),
    ]) {
      final market = gateway(FakeTransport((_) async => response));
      final result = await market.bankRates();
      expect(result.state, MarketState.failed, reason: response.body);
    }
  });
}
