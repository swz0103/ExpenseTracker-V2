import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';

import 'intraday.dart';
import 'market_data.dart';

enum PriceAlertDirection { atOrAbove, atOrBelow }

enum PriceRelation { below, equal, above }

final class PriceAlert {
  PriceAlert({
    required this.id,
    required this.instrumentId,
    required this.symbol,
    required this.target,
    required this.direction,
    this.cooldown = const Duration(hours: 6),
    this.enabled = true,
  }) {
    if (symbol.trim().isEmpty || symbol.length > 32) {
      throw ArgumentError.value(symbol, 'symbol');
    }
    if (cooldown < Duration.zero || cooldown > const Duration(days: 30)) {
      throw ArgumentError.value(cooldown, 'cooldown');
    }
  }

  final PublicId id;
  final PublicId instrumentId;
  final String symbol;
  final ShareUnitPrice target;
  final PriceAlertDirection direction;
  final Duration cooldown;
  final bool enabled;
}

final class PriceAlertCheckpoint {
  const PriceAlertCheckpoint({
    this.lastRelation,
    this.lastObservationDate,
    this.lastObservationAt,
    this.lastPrice,
    this.lastProviderId,
    this.lastNotifiedAt,
  });

  final PriceRelation? lastRelation;
  final BusinessDate? lastObservationDate;
  final UtcInstant? lastObservationAt;
  final String? lastPrice;
  final String? lastProviderId;
  final UtcInstant? lastNotifiedAt;
}

final class PriceAlertNotification {
  const PriceAlertNotification({
    required this.alertId,
    required this.instrumentId,
    required this.symbol,
    required this.price,
    required this.currency,
    required this.observedOn,
    this.observedAt,
    required this.providerId,
    required this.evaluatedAt,
  });

  final PublicId alertId;
  final PublicId instrumentId;
  final String symbol;
  final String price;
  final Currency currency;
  final BusinessDate observedOn;
  final UtcInstant? observedAt;
  final String providerId;
  final UtcInstant evaluatedAt;
}

final class PriceAlertEvaluation {
  const PriceAlertEvaluation({
    required this.checkpoint,
    this.notification,
    this.reason,
  });

  final PriceAlertCheckpoint checkpoint;
  final PriceAlertNotification? notification;
  final String? reason;
}

PriceAlertEvaluation evaluatePriceAlert({
  required PriceAlert alert,
  required PriceAlertCheckpoint checkpoint,
  required MarketResult<StockClose> result,
  required String providerId,
  required UtcInstant now,
}) {
  if (result.state != MarketState.available || result.value == null) {
    return PriceAlertEvaluation(
      checkpoint: checkpoint,
      reason: 'Only fresh available observations may trigger alerts',
    );
  }
  final observation = result.value!;
  return _evaluateObservation(
    alert: alert,
    checkpoint: checkpoint,
    symbol: observation.symbol,
    decimalPrice: observation.decimalPrice,
    observedOn: observation.asOf,
    providerId: providerId,
    now: now,
  );
}

PriceAlertEvaluation evaluateIntradayPriceAlert({
  required PriceAlert alert,
  required PriceAlertCheckpoint checkpoint,
  required MarketResult<IntradayBar> result,
  required String providerId,
  required UtcInstant now,
}) {
  if (result.state != MarketState.available || result.value == null) {
    return PriceAlertEvaluation(
      checkpoint: checkpoint,
      reason: 'Only fresh available observations may trigger alerts',
    );
  }
  final observation = result.value!;
  final instant = observation.startsAt.value;
  return _evaluateObservation(
    alert: alert,
    checkpoint: checkpoint,
    symbol: observation.symbol,
    decimalPrice: observation.close,
    observedOn: BusinessDate(instant.year, instant.month, instant.day),
    observedAt: observation.startsAt,
    providerId: providerId,
    now: now,
  );
}

PriceAlertEvaluation _evaluateObservation({
  required PriceAlert alert,
  required PriceAlertCheckpoint checkpoint,
  required String symbol,
  required String decimalPrice,
  required BusinessDate observedOn,
  required String providerId,
  required UtcInstant now,
  UtcInstant? observedAt,
}) {
  if (!alert.enabled) {
    return PriceAlertEvaluation(
      checkpoint: checkpoint,
      reason: 'Alert disabled',
    );
  }
  if (providerId.isEmpty) {
    throw ArgumentError.value(providerId, 'providerId');
  }
  if (symbol != alert.symbol) {
    return PriceAlertEvaluation(
      checkpoint: checkpoint,
      reason: 'Observation symbol does not match alert',
    );
  }
  final observedPrice = ShareUnitPrice.parse(
    alert.target.currency,
    decimalPrice,
  );
  final relation = _compare(observedPrice, alert.target);
  if (checkpoint.lastObservationDate == observedOn &&
      checkpoint.lastObservationAt == observedAt &&
      checkpoint.lastPrice == decimalPrice &&
      checkpoint.lastProviderId == providerId) {
    return PriceAlertEvaluation(
      checkpoint: checkpoint,
      reason: 'Observation already evaluated',
    );
  }
  final next = PriceAlertCheckpoint(
    lastRelation: relation,
    lastObservationDate: observedOn,
    lastObservationAt: observedAt,
    lastPrice: decimalPrice,
    lastProviderId: providerId,
    lastNotifiedAt: checkpoint.lastNotifiedAt,
  );
  final crossed = switch (alert.direction) {
    PriceAlertDirection.atOrAbove =>
      checkpoint.lastRelation == PriceRelation.below &&
          relation != PriceRelation.below,
    PriceAlertDirection.atOrBelow =>
      checkpoint.lastRelation == PriceRelation.above &&
          relation != PriceRelation.above,
  };
  if (!crossed) {
    return PriceAlertEvaluation(
      checkpoint: next,
      reason: 'Threshold not crossed',
    );
  }
  final lastNotified = checkpoint.lastNotifiedAt?.value;
  if (lastNotified != null &&
      now.value.difference(lastNotified) < alert.cooldown) {
    // The crossing stays pending: once the cooldown ends, a price still
    // past the target alerts (health check G2-26).
    return PriceAlertEvaluation(
      checkpoint: PriceAlertCheckpoint(
        lastRelation: checkpoint.lastRelation,
        lastObservationDate: observedOn,
        lastObservationAt: observedAt,
        lastPrice: decimalPrice,
        lastProviderId: providerId,
        lastNotifiedAt: checkpoint.lastNotifiedAt,
      ),
      reason: 'Alert is cooling down',
    );
  }
  final notifiedCheckpoint = PriceAlertCheckpoint(
    lastRelation: relation,
    lastObservationDate: observedOn,
    lastObservationAt: observedAt,
    lastPrice: decimalPrice,
    lastProviderId: providerId,
    lastNotifiedAt: now,
  );
  return PriceAlertEvaluation(
    checkpoint: notifiedCheckpoint,
    notification: PriceAlertNotification(
      alertId: alert.id,
      instrumentId: alert.instrumentId,
      symbol: alert.symbol,
      price: decimalPrice,
      currency: alert.target.currency,
      observedOn: observedOn,
      observedAt: observedAt,
      providerId: providerId,
      evaluatedAt: now,
    ),
  );
}

final class PriceAlertCheckpointCodec {
  const PriceAlertCheckpointCodec();

  String encode(PriceAlertCheckpoint checkpoint) => jsonEncode({
    'version': 2,
    'lastRelation': checkpoint.lastRelation?.name,
    'lastObservationDate': checkpoint.lastObservationDate?.toString(),
    'lastObservationAt': checkpoint.lastObservationAt?.toString(),
    'lastPrice': checkpoint.lastPrice,
    'lastProviderId': checkpoint.lastProviderId,
    'lastNotifiedAt': checkpoint.lastNotifiedAt?.toString(),
  });

  PriceAlertCheckpoint decode(String source) {
    final raw = jsonDecode(source);
    if (raw is! Map<String, dynamic> ||
        raw['version'] != 1 && raw['version'] != 2) {
      throw const FormatException('Unsupported price alert checkpoint');
    }
    final relation = raw['lastRelation'];
    final date = raw['lastObservationDate'];
    final instant = raw['lastObservationAt'];
    final price = raw['lastPrice'];
    final provider = raw['lastProviderId'];
    final notified = raw['lastNotifiedAt'];
    if (relation != null && relation is! String ||
        date != null && date is! String ||
        instant != null && instant is! String ||
        price != null && price is! String ||
        provider != null && provider is! String ||
        notified != null && notified is! String) {
      throw const FormatException('Invalid price alert checkpoint');
    }
    return PriceAlertCheckpoint(
      lastRelation: relation == null
          ? null
          : PriceRelation.values.firstWhere(
              (value) => value.name == relation,
              orElse: () => throw const FormatException('Invalid relation'),
            ),
      lastObservationDate: date == null ? null : BusinessDate.parse(date),
      lastObservationAt: instant == null ? null : UtcInstant.parse(instant),
      lastPrice: price,
      lastProviderId: provider,
      lastNotifiedAt: notified == null ? null : UtcInstant.parse(notified),
    );
  }
}

PriceRelation _compare(ShareUnitPrice left, ShareUnitPrice right) {
  if (left.currency != right.currency) {
    throw ArgumentError('Cannot compare prices in different currencies');
  }
  final scale = left.scale > right.scale ? left.scale : right.scale;
  final leftValue = left.coefficient * _pow10(scale - left.scale);
  final rightValue = right.coefficient * _pow10(scale - right.scale);
  final compared = leftValue.compareTo(rightValue);
  if (compared < 0) return PriceRelation.below;
  if (compared > 0) return PriceRelation.above;
  return PriceRelation.equal;
}

BigInt _pow10(int exponent) {
  var result = BigInt.one;
  for (var i = 0; i < exponent; i++) {
    result *= BigInt.from(10);
  }
  return result;
}
