import 'package:expense_preview/price_alert_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';

final class _MemoryStore implements PriceAlertRecordStore {
  final values = <PublicId, String>{};

  @override
  Future<String?> read(PublicId instrumentId) async => values[instrumentId];

  @override
  Future<void> write(PublicId instrumentId, String value) async {
    values[instrumentId] = value;
  }

  @override
  Future<void> delete(PublicId instrumentId) async {
    values.remove(instrumentId);
  }
}

void main() {
  final currency = Currency('TWD', 2);
  late InvestmentInstrument instrument;
  late _MemoryStore store;
  late PriceAlertService service;

  setUp(() {
    instrument = InvestmentInstrument(
      id: PublicId.generate(),
      kind: InstrumentKind.stock,
      marketCode: 'TWSE',
      symbol: '2330',
      name: '測試股票',
      tradingCurrency: currency,
    );
    store = _MemoryStore();
    service = PriceAlertService(store);
  });

  test('saved alert round trips exact target and can be deleted', () async {
    final saved = await service.save(
      instrument: instrument,
      target: ShareUnitPrice.parse(currency, '1500.125'),
      direction: PriceAlertDirection.atOrAbove,
    );
    final loaded = await service.load(instrument);
    expect(loaded!.alert.id, saved.alert.id);
    expect(loaded.alert.target.toString(), '1500.125');
    expect(loaded.alert.direction, PriceAlertDirection.atOrAbove);
    await service.delete(instrument);
    expect(await service.load(instrument), isNull);
  });

  test('v2 alert carries encrypted background worker metadata', () async {
    await service.save(
      instrument: instrument,
      target: ShareUnitPrice.parse(currency, '1510'),
      direction: PriceAlertDirection.atOrAbove,
      backgroundEnabled: true,
    );
    final loaded = await service.loadById(instrument.id);
    expect(loaded!.backgroundEnabled, isTrue);
    expect(loaded.instrument!.id, instrument.id);
    expect(loaded.instrument!.kind, InstrumentKind.stock);
    expect(loaded.instrument!.marketCode, 'TWSE');
    expect(loaded.instrument!.name, '測試股票');
  });

  test('fresh observations arm then emit only after crossing', () async {
    await service.save(
      instrument: instrument,
      target: ShareUnitPrice.parse(currency, '1500.00'),
      direction: PriceAlertDirection.atOrAbove,
    );
    final first = await service.evaluate(
      instrument: instrument,
      result: MarketResult(
        MarketState.available,
        value: StockClose(
          symbol: '2330',
          decimalPrice: '1499.00',
          asOf: BusinessDate(2026, 10, 1),
          fetchedAt: UtcInstant(DateTime.utc(2026, 10, 1)),
        ),
      ),
      providerId: StockClose.provider,
      now: UtcInstant(DateTime.utc(2026, 10, 1, 8)),
    );
    expect(first!.notification, isNull);
    final crossed = await service.evaluate(
      instrument: instrument,
      result: MarketResult(
        MarketState.available,
        value: StockClose(
          symbol: '2330',
          decimalPrice: '1500.00',
          asOf: BusinessDate(2026, 10, 2),
          fetchedAt: UtcInstant(DateTime.utc(2026, 10, 2)),
        ),
      ),
      providerId: StockClose.provider,
      now: UtcInstant(DateTime.utc(2026, 10, 2, 8)),
    );
    expect(crossed!.notification!.price, '1500.00');
    expect(
      (await service.load(instrument))!.checkpoint.lastNotifiedAt,
      isNotNull,
    );
  });

  test('changing threshold resets the prior comparison checkpoint', () async {
    await service.save(
      instrument: instrument,
      target: ShareUnitPrice.parse(currency, '1500'),
      direction: PriceAlertDirection.atOrAbove,
    );
    await service.evaluate(
      instrument: instrument,
      result: MarketResult(
        MarketState.available,
        value: StockClose(
          symbol: '2330',
          decimalPrice: '1400',
          asOf: BusinessDate(2026, 10, 1),
          fetchedAt: UtcInstant(DateTime.utc(2026, 10, 1)),
        ),
      ),
      providerId: StockClose.provider,
      now: UtcInstant(DateTime.utc(2026, 10, 1)),
    );
    final changed = await service.save(
      instrument: instrument,
      target: ShareUnitPrice.parse(currency, '1600'),
      direction: PriceAlertDirection.atOrAbove,
    );
    expect(changed.checkpoint.lastRelation, isNull);
  });

  test('mismatched or corrupt persisted data fails closed', () async {
    store.values[instrument.id] = '{}';
    expect(() => service.load(instrument), throwsFormatException);
  });

  test('intraday observations persist minute-level crossing state', () async {
    await service.save(
      instrument: instrument,
      target: ShareUnitPrice.parse(currency, '1500'),
      direction: PriceAlertDirection.atOrAbove,
    );
    MarketResult<IntradayBar> result(String price, int minute) => MarketResult(
      MarketState.available,
      value: IntradayBar(
        symbol: instrument.symbol,
        interval: IntradayInterval.oneMinute,
        startsAt: UtcInstant(DateTime.utc(2026, 10, 1, 1, minute)),
        open: price,
        high: price,
        low: price,
        close: price,
        volume: BigInt.one,
        fetchedAt: UtcInstant(DateTime.utc(2026, 10, 1, 1, minute, 30)),
      ),
    );
    await service.evaluateIntraday(
      instrument: instrument,
      result: result('1499', 1),
      providerId: 'intraday-test',
      now: UtcInstant(DateTime.utc(2026, 10, 1, 1, 2)),
    );
    final crossed = await service.evaluateIntraday(
      instrument: instrument,
      result: result('1501', 2),
      providerId: 'intraday-test',
      now: UtcInstant(DateTime.utc(2026, 10, 1, 1, 3)),
    );
    expect(crossed!.notification!.price, '1501');
    expect(
      (await service.load(instrument))!.checkpoint.lastObservationAt,
      UtcInstant(DateTime.utc(2026, 10, 1, 1, 2)),
    );
  });
}
