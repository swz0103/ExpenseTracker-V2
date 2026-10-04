import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';

import 'market_data.dart';

final class FrankfurterReferenceFxGateway {
  FrankfurterReferenceFxGateway({
    required MarketTransport transport,
    DateTime Function()? clock,
    this.cacheTtl = const Duration(hours: 12),
    this.maximumObservationAge = const Duration(days: 4),
  }) : _transport = transport,
       _clock = clock ?? DateTime.now {
    if (cacheTtl <= Duration.zero || maximumObservationAge < Duration.zero) {
      throw ArgumentError('Invalid Frankfurter time policy');
    }
  }

  static const providerId = 'frankfurter-central-bank-reference';
  final MarketTransport _transport;
  final DateTime Function() _clock;
  final Duration cacheTtl;
  final Duration maximumObservationAge;
  final Map<Uri, ({MarketResponse response, UtcInstant fetchedAt})> _cache = {};
  final Map<Uri, Future<({MarketResponse response, UtcInstant fetchedAt})>>
  _pending = {};

  Future<MarketResult<ReferenceRate>> rate(
    Currency base,
    Currency quote, {
    BusinessDate? requiredAsOf,
  }) async {
    if (base == quote) {
      return const MarketResult(
        MarketState.unsupported,
        reason: 'FX base and quote must differ',
      );
    }
    final uri = Uri.https(
      'api.frankfurter.dev',
      '/v2/rate/${base.code.toLowerCase()}/${quote.code.toLowerCase()}',
      requiredAsOf == null ? null : {'date': requiredAsOf.toString()},
    );
    late final ({MarketResponse response, UtcInstant fetchedAt}) fetched;
    try {
      fetched = await _fetch(uri);
    } catch (_) {
      return const MarketResult(
        MarketState.failed,
        reason: 'Frankfurter request failed',
      );
    }
    final response = fetched.response;
    if (response.statusCode == 404 || response.statusCode == 422) {
      return const MarketResult(
        MarketState.missing,
        reason: 'Frankfurter has no rate for this pair or date',
      );
    }
    if (response.statusCode == 429) {
      return const MarketResult(
        MarketState.throttled,
        reason: 'Frankfurter request limit reached',
      );
    }
    if (response.statusCode != 200) {
      return const MarketResult(
        MarketState.failed,
        reason: 'Frankfurter request failed',
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      // Extra fields are ignored, so an additive change on the provider's
      // side is not an outage (health check G2-23).
      if (decoded is! Map<String, dynamic> ||
          decoded['date'] is! String ||
          decoded['base'] != base.code ||
          decoded['quote'] != quote.code ||
          decoded['rate'] is! num) {
        throw const FormatException('Invalid Frankfurter response');
      }
      // The exact digits, exponent included: 6.14e-05 is not 6.14
      // (health check G2-06).
      final number = _exactRate.firstMatch(response.body)?[1];
      if (number == null) {
        throw const FormatException('Missing exact Frankfurter rate');
      }
      final decimal = plainDecimal(number);
      final parsed = (decoded['rate'] as num).toDouble();
      if ((double.parse(decimal) - parsed).abs() > parsed.abs() * 1e-9) {
        throw const FormatException('Ambiguous Frankfurter rate');
      }
      final asOf = BusinessDate.parse(decoded['date'] as String);
      final observationAge = _ageInDays(asOf, fetched.fetchedAt.value);
      if (observationAge < 0) {
        throw const FormatException('Future Frankfurter observation');
      }
      if (requiredAsOf != null && asOf.compareTo(requiredAsOf) > 0) {
        throw const FormatException('Future Frankfurter observation');
      }
      final observation = FxObservation(
        rate: FxRate.parse(base, quote, decimal),
        source: providerId,
        asOf: asOf,
        retrievedAt: fetched.fetchedAt,
      );
      final stale = requiredAsOf != null
          ? asOf != requiredAsOf
          : observationAge > maximumObservationAge.inDays;
      return MarketResult(
        stale ? MarketState.stale : MarketState.available,
        value: ReferenceRate(observation: observation, derivedInverse: false),
        reason: stale
            ? 'Frankfurter observation predates requested date'
            : null,
      );
    } on FormatException {
      return const MarketResult(
        MarketState.failed,
        reason: 'Invalid Frankfurter response',
      );
    } on FxException {
      return const MarketResult(
        MarketState.failed,
        reason: 'Invalid Frankfurter rate',
      );
    }
  }

  Future<({MarketResponse response, UtcInstant fetchedAt})> _fetch(
    Uri uri,
  ) async {
    final now = _clock().toUtc();
    final cached = _cache[uri];
    if (cached != null &&
        now.difference(cached.fetchedAt.value) >= Duration.zero &&
        now.difference(cached.fetchedAt.value) < cacheTtl) {
      return cached;
    }
    final running = _pending[uri];
    if (running != null) return running;
    final future = () async {
      final result = (
        response: await _transport.get(uri),
        fetchedAt: UtcInstant(now),
      );
      if (result.response.statusCode == 200) _cache[uri] = result;
      return result;
    }();
    _pending[uri] = future;
    try {
      return await future;
    } finally {
      _pending.remove(uri);
    }
  }
}

int _ageInDays(BusinessDate date, DateTime now) => DateTime.utc(
  now.year,
  now.month,
  now.day,
).difference(DateTime.utc(date.year, date.month, date.day)).inDays;

/// A JSON number such as `6.14e-05` as plain decimal text, `0.0000614`,
/// without passing through a double.
String plainDecimal(String number) {
  final match = _jsonNumber.firstMatch(number);
  if (match == null) throw const FormatException('Invalid decimal');
  final whole = match[1]!;
  final fraction = match[2] ?? '';
  final exponent = int.parse(match[3] ?? '0');
  if (exponent.abs() > 40) throw const FormatException('Invalid decimal');
  var digits = whole + fraction;
  var point = whole.length + exponent;
  if (point <= 0) {
    digits = '0' * (1 - point) + digits;
    point = 1;
  } else if (point > digits.length) {
    digits = digits + '0' * (point - digits.length);
  }
  final integer = digits.substring(0, point).replaceFirst(RegExp(r'^0+'), '');
  final rest = digits.substring(point).replaceFirst(RegExp(r'0+$'), '');
  final head = integer.isEmpty ? '0' : integer;
  return rest.isEmpty ? head : '$head.$rest';
}

final _exactRate = RegExp(
  r'"rate"\s*:\s*([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)',
);
final _jsonNumber = RegExp(r'^([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$');
