import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';

abstract interface class PriceAlertRecordStore {
  Future<String?> read(PublicId instrumentId);
  Future<void> write(PublicId instrumentId, String value);
  Future<void> delete(PublicId instrumentId);
}

abstract interface class PriceAlertNotificationPresenter {
  Future<bool> show(PriceAlertNotification notification);
}

final class SavedPriceAlert {
  const SavedPriceAlert({required this.alert, required this.checkpoint});

  final PriceAlert alert;
  final PriceAlertCheckpoint checkpoint;
}

final class PriceAlertService {
  const PriceAlertService(this._store);

  final PriceAlertRecordStore _store;

  Future<SavedPriceAlert?> load(InvestmentInstrument instrument) async {
    final raw = await _store.read(instrument.id);
    if (raw == null) return null;
    final saved = _decode(raw);
    if (saved.alert.instrumentId != instrument.id ||
        saved.alert.symbol != instrument.symbol ||
        saved.alert.target.currency != instrument.tradingCurrency) {
      throw const FormatException('Price alert does not match instrument');
    }
    return saved;
  }

  Future<SavedPriceAlert> save({
    required InvestmentInstrument instrument,
    required ShareUnitPrice target,
    required PriceAlertDirection direction,
  }) async {
    if (target.currency != instrument.tradingCurrency) {
      throw ArgumentError('Price alert currency must match instrument');
    }
    SavedPriceAlert? prior;
    try {
      prior = await load(instrument);
    } on FormatException {
      prior = null;
    }
    final unchanged =
        prior?.alert.target == target && prior?.alert.direction == direction;
    final saved = SavedPriceAlert(
      alert: PriceAlert(
        id: prior?.alert.id ?? PublicId.generate(),
        instrumentId: instrument.id,
        symbol: instrument.symbol,
        target: target,
        direction: direction,
      ),
      checkpoint: unchanged ? prior!.checkpoint : const PriceAlertCheckpoint(),
    );
    await _store.write(instrument.id, _encode(saved));
    return saved;
  }

  Future<void> delete(InvestmentInstrument instrument) =>
      _store.delete(instrument.id);

  Future<PriceAlertEvaluation?> evaluate({
    required InvestmentInstrument instrument,
    required MarketResult<StockClose> result,
    required String providerId,
    required UtcInstant now,
  }) async {
    final saved = await load(instrument);
    if (saved == null) return null;
    final evaluation = evaluatePriceAlert(
      alert: saved.alert,
      checkpoint: saved.checkpoint,
      result: result,
      providerId: providerId,
      now: now,
    );
    if (!identical(evaluation.checkpoint, saved.checkpoint)) {
      await _store.write(
        instrument.id,
        _encode(
          SavedPriceAlert(
            alert: saved.alert,
            checkpoint: evaluation.checkpoint,
          ),
        ),
      );
    }
    return evaluation;
  }

  Future<PriceAlertEvaluation?> evaluateIntraday({
    required InvestmentInstrument instrument,
    required MarketResult<IntradayBar> result,
    required String providerId,
    required UtcInstant now,
  }) async {
    final saved = await load(instrument);
    if (saved == null) return null;
    final evaluation = evaluateIntradayPriceAlert(
      alert: saved.alert,
      checkpoint: saved.checkpoint,
      result: result,
      providerId: providerId,
      now: now,
    );
    if (!identical(evaluation.checkpoint, saved.checkpoint)) {
      await _store.write(
        instrument.id,
        _encode(
          SavedPriceAlert(
            alert: saved.alert,
            checkpoint: evaluation.checkpoint,
          ),
        ),
      );
    }
    return evaluation;
  }
}

String _encode(SavedPriceAlert saved) => jsonEncode({
  'version': 1,
  'id': saved.alert.id.value,
  'instrumentId': saved.alert.instrumentId.value,
  'symbol': saved.alert.symbol,
  'currency': saved.alert.target.currency.code,
  'currencyScale': saved.alert.target.currency.scale,
  'target': saved.alert.target.toString(),
  'direction': saved.alert.direction.name,
  'cooldownSeconds': saved.alert.cooldown.inSeconds,
  'enabled': saved.alert.enabled,
  'checkpoint': const PriceAlertCheckpointCodec().encode(saved.checkpoint),
});

SavedPriceAlert _decode(String source) {
  final raw = jsonDecode(source);
  if (raw is! Map<String, dynamic> ||
      raw.length != 11 ||
      raw['version'] != 1 ||
      raw['id'] is! String ||
      raw['instrumentId'] is! String ||
      raw['symbol'] is! String ||
      raw['currency'] is! String ||
      raw['currencyScale'] is! int ||
      raw['target'] is! String ||
      raw['direction'] is! String ||
      raw['cooldownSeconds'] is! int ||
      raw['enabled'] is! bool ||
      raw['checkpoint'] is! String) {
    throw const FormatException('Invalid saved price alert');
  }
  try {
    final currency = Currency(
      raw['currency'] as String,
      raw['currencyScale'] as int,
    );
    final direction = PriceAlertDirection.values.firstWhere(
      (value) => value.name == raw['direction'],
      orElse: () => throw const FormatException('Invalid alert direction'),
    );
    return SavedPriceAlert(
      alert: PriceAlert(
        id: PublicId.parse(raw['id'] as String),
        instrumentId: PublicId.parse(raw['instrumentId'] as String),
        symbol: raw['symbol'] as String,
        target: ShareUnitPrice.parse(currency, raw['target'] as String),
        direction: direction,
        cooldown: Duration(seconds: raw['cooldownSeconds'] as int),
        enabled: raw['enabled'] as bool,
      ),
      checkpoint: const PriceAlertCheckpointCodec().decode(
        raw['checkpoint'] as String,
      ),
    );
  } on ArgumentError {
    throw const FormatException('Invalid saved price alert');
  } on MoneyException {
    throw const FormatException('Invalid saved price alert');
  } on InvestmentException {
    throw const FormatException('Invalid saved price alert');
  }
}
