import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';
import 'package:test/test.dart';

void main() {
  final twd = Currency('TWD', 2);
  late PriceAlert alert;
  late UtcInstant now;

  setUp(() {
    alert = PriceAlert(
      id: PublicId.generate(),
      instrumentId: PublicId.generate(),
      symbol: '2330',
      target: ShareUnitPrice.parse(twd, '1500'),
      direction: PriceAlertDirection.atOrAbove,
    );
    now = UtcInstant(DateTime.utc(2026, 10, 1, 5));
  });

  test('arms below target then emits once when a fresh price crosses', () {
    final armed = evaluatePriceAlert(
      alert: alert,
      checkpoint: const PriceAlertCheckpoint(),
      result: _result('1499', BusinessDate(2026, 10, 1)),
      providerId: StockClose.provider,
      now: now,
    );
    expect(armed.notification, isNull);
    expect(armed.checkpoint.lastRelation, PriceRelation.below);

    final crossed = evaluatePriceAlert(
      alert: alert,
      checkpoint: armed.checkpoint,
      result: _result('1500.00', BusinessDate(2026, 10, 2)),
      providerId: StockClose.provider,
      now: UtcInstant(now.value.add(const Duration(days: 1))),
    );
    expect(crossed.notification!.price, '1500.00');
    expect(crossed.notification!.observedOn, BusinessDate(2026, 10, 2));
    expect(crossed.checkpoint.lastNotifiedAt, isNotNull);

    final duplicate = evaluatePriceAlert(
      alert: alert,
      checkpoint: crossed.checkpoint,
      result: _result('1500.00', BusinessDate(2026, 10, 2)),
      providerId: StockClose.provider,
      now: UtcInstant(now.value.add(const Duration(days: 1, minutes: 1))),
    );
    expect(duplicate.notification, isNull);
    expect(duplicate.reason, 'Observation already evaluated');
  });

  test('stale, failed and missing observations never trigger', () {
    final checkpoint = PriceAlertCheckpoint(lastRelation: PriceRelation.below);
    for (final state in [
      MarketState.stale,
      MarketState.failed,
      MarketState.missing,
    ]) {
      final evaluation = evaluatePriceAlert(
        alert: alert,
        checkpoint: checkpoint,
        result: MarketResult(
          state,
          value: state == MarketState.stale
              ? _close('1600', BusinessDate(2026, 10, 1))
              : null,
        ),
        providerId: StockClose.provider,
        now: now,
      );
      expect(evaluation.notification, isNull);
      expect(evaluation.checkpoint.lastRelation, PriceRelation.below);
    }
  });

  test(
    'cooldown suppresses a second crossing while retaining new relation',
    () {
      final checkpoint = PriceAlertCheckpoint(
        lastRelation: PriceRelation.below,
        lastNotifiedAt: UtcInstant(
          now.value.subtract(const Duration(hours: 1)),
        ),
      );
      final evaluation = evaluatePriceAlert(
        alert: alert,
        checkpoint: checkpoint,
        result: _result('1600', BusinessDate(2026, 10, 1)),
        providerId: StockClose.provider,
        now: now,
      );
      expect(evaluation.notification, isNull);
      expect(evaluation.reason, 'Alert is cooling down');
      expect(evaluation.checkpoint.lastRelation, PriceRelation.above);
    },
  );

  test('below alert crosses in the opposite direction with exact decimals', () {
    final below = PriceAlert(
      id: PublicId.generate(),
      instrumentId: alert.instrumentId,
      symbol: '2330',
      target: ShareUnitPrice.parse(twd, '10.5'),
      direction: PriceAlertDirection.atOrBelow,
      cooldown: Duration.zero,
    );
    final evaluation = evaluatePriceAlert(
      alert: below,
      checkpoint: const PriceAlertCheckpoint(lastRelation: PriceRelation.above),
      result: _result('10.50', BusinessDate(2026, 10, 1)),
      providerId: StockClose.provider,
      now: now,
    );
    expect(evaluation.notification, isNotNull);
    expect(evaluation.checkpoint.lastRelation, PriceRelation.equal);
  });

  test('checkpoint round trip preserves durable de-duplication state', () {
    final checkpoint = PriceAlertCheckpoint(
      lastRelation: PriceRelation.above,
      lastObservationDate: BusinessDate(2026, 10, 1),
      lastObservationAt: UtcInstant(DateTime.utc(2026, 10, 1, 4, 55)),
      lastPrice: '1500.00',
      lastProviderId: StockClose.provider,
      lastNotifiedAt: now,
    );
    const codec = PriceAlertCheckpointCodec();
    final restored = codec.decode(codec.encode(checkpoint));
    expect(restored.lastRelation, checkpoint.lastRelation);
    expect(restored.lastObservationDate, checkpoint.lastObservationDate);
    expect(restored.lastObservationAt, checkpoint.lastObservationAt);
    expect(restored.lastPrice, checkpoint.lastPrice);
    expect(restored.lastProviderId, checkpoint.lastProviderId);
    expect(restored.lastNotifiedAt, checkpoint.lastNotifiedAt);
    expect(() => codec.decode('{"version":3}'), throwsFormatException);
  });

  test('version one checkpoint remains readable after intraday migration', () {
    const source =
        '{"version":1,"lastRelation":"below","lastObservationDate":"2026-10-01","lastPrice":"1499","lastProviderId":"daily","lastNotifiedAt":null}';
    final restored = const PriceAlertCheckpointCodec().decode(source);
    expect(restored.lastRelation, PriceRelation.below);
    expect(restored.lastObservationAt, isNull);
  });

  test('distinct intraday bars can arm and cross on the same day', () {
    MarketResult<IntradayBar> bar(String price, int minute) => MarketResult(
      MarketState.available,
      value: IntradayBar(
        symbol: '2330',
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
    final armed = evaluateIntradayPriceAlert(
      alert: alert,
      checkpoint: const PriceAlertCheckpoint(),
      result: bar('1499', 1),
      providerId: 'intraday-test',
      now: now,
    );
    final crossed = evaluateIntradayPriceAlert(
      alert: alert,
      checkpoint: armed.checkpoint,
      result: bar('1501', 2),
      providerId: 'intraday-test',
      now: UtcInstant(now.value.add(const Duration(minutes: 1))),
    );
    expect(crossed.notification!.price, '1501');
    expect(
      crossed.notification!.observedAt,
      UtcInstant(DateTime.utc(2026, 10, 1, 1, 2)),
    );
    final duplicate = evaluateIntradayPriceAlert(
      alert: alert,
      checkpoint: crossed.checkpoint,
      result: bar('1501', 2),
      providerId: 'intraday-test',
      now: UtcInstant(now.value.add(const Duration(minutes: 2))),
    );
    expect(duplicate.notification, isNull);
    expect(duplicate.reason, 'Observation already evaluated');
  });
}

MarketResult<StockClose> _result(String price, BusinessDate date) =>
    MarketResult(MarketState.available, value: _close(price, date));

StockClose _close(String price, BusinessDate date) => StockClose(
  symbol: '2330',
  decimalPrice: price,
  asOf: date,
  fetchedAt: UtcInstant(DateTime.utc(2026, 10, 1, 4)),
);
