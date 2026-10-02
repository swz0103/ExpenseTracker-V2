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

abstract interface class PriceAlertBackgroundScheduler {
  bool supports(InvestmentInstrument instrument);

  /// Returns false when Android notification permission was denied.
  Future<bool> synchronize(SavedPriceAlert saved);

  Future<void> cancel(PublicId instrumentId);
}

final class SavedPriceAlert {
  const SavedPriceAlert({
    required this.alert,
    required this.checkpoint,
    required this.instrument,
    required this.backgroundEnabled,
  });

  final PriceAlert alert;
  final PriceAlertCheckpoint checkpoint;
  final InvestmentInstrument? instrument;
  final bool backgroundEnabled;
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
        saved.alert.target.currency != instrument.tradingCurrency ||
        saved.instrument != null &&
            (saved.instrument!.kind != instrument.kind ||
                saved.instrument!.marketCode != instrument.marketCode ||
                saved.instrument!.name != instrument.name)) {
      throw const FormatException('Price alert does not match instrument');
    }
    return saved;
  }

  /// Reads a self-contained v2 record for a headless background worker.
  /// Legacy v1 records deliberately return null until the user saves them again.
  Future<SavedPriceAlert?> loadById(PublicId instrumentId) async {
    final raw = await _store.read(instrumentId);
    if (raw == null) return null;
    final saved = _decode(raw);
    if (saved.alert.instrumentId != instrumentId || saved.instrument == null) {
      return null;
    }
    return saved;
  }

  Future<SavedPriceAlert> save({
    required InvestmentInstrument instrument,
    required ShareUnitPrice target,
    required PriceAlertDirection direction,
    bool? backgroundEnabled,
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
      instrument: instrument,
      backgroundEnabled: backgroundEnabled ?? prior?.backgroundEnabled ?? false,
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
    bool Function()? isActive,
  }) async {
    final saved = await load(instrument);
    if (saved == null || isActive != null && !isActive()) return null;
    final evaluation = evaluatePriceAlert(
      alert: saved.alert,
      checkpoint: saved.checkpoint,
      result: result,
      providerId: providerId,
      now: now,
    );
    if (isActive != null && !isActive()) return null;
    if (!identical(evaluation.checkpoint, saved.checkpoint)) {
      await _store.write(
        instrument.id,
        _encode(
          SavedPriceAlert(
            alert: saved.alert,
            checkpoint: evaluation.checkpoint,
            instrument: saved.instrument ?? instrument,
            backgroundEnabled: saved.backgroundEnabled,
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
    bool Function()? isActive,
  }) async {
    final saved = await load(instrument);
    if (saved == null || isActive != null && !isActive()) return null;
    final evaluation = evaluateIntradayPriceAlert(
      alert: saved.alert,
      checkpoint: saved.checkpoint,
      result: result,
      providerId: providerId,
      now: now,
    );
    if (isActive != null && !isActive()) return null;
    if (!identical(evaluation.checkpoint, saved.checkpoint)) {
      await _store.write(
        instrument.id,
        _encode(
          SavedPriceAlert(
            alert: saved.alert,
            checkpoint: evaluation.checkpoint,
            instrument: saved.instrument ?? instrument,
            backgroundEnabled: saved.backgroundEnabled,
          ),
        ),
      );
    }
    return evaluation;
  }
}

String _encode(SavedPriceAlert saved) => jsonEncode({
  'version': 2,
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
  'instrument': {
    'kind': saved.instrument?.kind.name,
    'marketCode': saved.instrument?.marketCode,
    'name': saved.instrument?.name,
  },
  'backgroundEnabled': saved.backgroundEnabled,
});

SavedPriceAlert _decode(String source) {
  final raw = jsonDecode(source);
  final version = raw is Map<String, dynamic> ? raw['version'] : null;
  if (raw is! Map<String, dynamic> ||
      (version != 1 && version != 2) ||
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
  if (version == 1 && raw.length != 11 ||
      version == 2 &&
          (raw.length != 13 ||
              raw['instrument'] is! Map<String, dynamic> ||
              raw['backgroundEnabled'] is! bool)) {
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
    InvestmentInstrument? instrument;
    if (version == 2) {
      final metadata = raw['instrument'] as Map<String, dynamic>;
      if (metadata.length != 3 ||
          metadata['kind'] is! String ||
          metadata['marketCode'] is! String ||
          metadata['name'] is! String) {
        throw const FormatException('Invalid alert instrument');
      }
      final kind = InstrumentKind.values.firstWhere(
        (value) => value.name == metadata['kind'],
        orElse: () => throw const FormatException('Invalid instrument kind'),
      );
      instrument = InvestmentInstrument(
        id: PublicId.parse(raw['instrumentId'] as String),
        kind: kind,
        marketCode: metadata['marketCode'] as String,
        symbol: raw['symbol'] as String,
        name: metadata['name'] as String,
        tradingCurrency: currency,
      );
    }
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
      instrument: instrument,
      backgroundEnabled: version == 2 && raw['backgroundEnabled'] as bool,
    );
  } on ArgumentError {
    throw const FormatException('Invalid saved price alert');
  } on MoneyException {
    throw const FormatException('Invalid saved price alert');
  } on InvestmentException {
    throw const FormatException('Invalid saved price alert');
  }
}
