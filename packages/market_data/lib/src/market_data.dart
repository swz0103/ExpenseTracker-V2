import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';

/// The provider date is distinct from the fetch time. Every value is
/// informational; a broker execution or bank conversion must use actual terms.
enum MarketState { available, stale, missing, unsupported, failed, throttled }

final class MarketResult<T> {
  const MarketResult(this.state, {this.value, this.reason});
  final MarketState state;
  final T? value;
  final String? reason;
}

final class StockClose {
  const StockClose({
    required this.symbol,
    required this.decimalPrice,
    required this.asOf,
    required this.fetchedAt,
  });
  static const provider = 'twse-stock-day-all';
  final String symbol;

  /// Exact positive TWD price per share; never a binary floating-point number.
  final String decimalPrice;
  final BusinessDate asOf;
  final UtcInstant fetchedAt;
}

final class ReferenceRate {
  const ReferenceRate({
    required this.observation,
    required this.derivedInverse,
  });
  static const provider = 'ecb-exr-daily';
  final FxObservation observation;

  /// True when the requested non-EUR/EUR rate is the inverse of ECB's EUR base.
  final bool derivedInverse;
}

final class MarketResponse {
  const MarketResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

abstract interface class MarketTransport {
  Future<MarketResponse> get(Uri uri);
}

/// Android/desktop transport with a finite response budget and no redirects.
final class IoMarketTransport implements MarketTransport {
  const IoMarketTransport();

  @override
  Future<MarketResponse> get(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, text/csv',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'ExpenseTracker-V2/market-data',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const FormatException('Market response too large');
        }
      }
      return MarketResponse(response.statusCode, utf8.decode(bytes));
    } finally {
      client.close(force: true);
    }
  }
}

final class _Snapshot {
  const _Snapshot(this.body, this.fetchedAt);
  final String body;
  final UtcInstant fetchedAt;
}

final class _Fetch {
  const _Fetch(this.snapshot, this.state, [this.reason]);
  final _Snapshot? snapshot;
  final MarketState state;
  final String? reason;
}

final class _EcbRow {
  const _EcbRow(this.asOf, this.decimal);
  final BusinessDate asOf;
  final String? decimal;
}

/// A single official source per route. Shared snapshot cache prevents one HTTP
/// request per holding, and cooldown prevents repeated requests on failures.
final class MarketDataGateway {
  MarketDataGateway({
    MarketTransport? transport,
    DateTime Function()? clock,
    this.cacheTtl = const Duration(minutes: 20),
    this.requestCooldown = const Duration(seconds: 10),
    this.maximumObservationAge = const Duration(days: 4),
  }) : _transport = transport ?? const IoMarketTransport(),
       _clock = clock ?? DateTime.now {
    if (cacheTtl <= Duration.zero ||
        requestCooldown < Duration.zero ||
        maximumObservationAge < Duration.zero) {
      throw ArgumentError('Invalid market data time policy');
    }
  }

  static final twseUri = Uri.https(
    'openapi.twse.com.tw',
    '/v1/exchangeReport/STOCK_DAY_ALL',
  );
  final MarketTransport _transport;
  final DateTime Function() _clock;
  final Duration cacheTtl;
  final Duration requestCooldown;
  final Duration maximumObservationAge;
  final Map<Uri, _Snapshot> _cache = {};
  final Map<String, DateTime> _lastAttempt = {};
  final Map<Uri, Future<_Fetch>> _pending = {};

  Future<MarketResult<StockClose>> stockClose(
    InvestmentInstrument instrument, {
    BusinessDate? requiredAsOf,
  }) async {
    if (instrument.marketCode != 'TWSE' ||
        instrument.tradingCurrency != Currency('TWD', 2) ||
        !_twseSymbolSupported(instrument)) {
      return const MarketResult(
        MarketState.unsupported,
        reason: 'Only TWSE TWD listed stocks and ETFs are supported',
      );
    }
    final fetched = await _fetch(twseUri);
    if (fetched.snapshot == null) {
      return MarketResult(fetched.state, reason: fetched.reason);
    }
    try {
      final decoded = jsonDecode(fetched.snapshot!.body);
      if (decoded is! List) throw const FormatException('Expected TWSE rows');
      Map<String, dynamic>? match;
      for (final row in decoded) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Invalid TWSE row');
        }
        if (row['Code'] == instrument.symbol) {
          if (match != null)
            throw const FormatException('Duplicate TWSE symbol');
          match = row;
        }
      }
      if (match == null)
        return const MarketResult(
          MarketState.missing,
          reason: 'Symbol absent from latest TWSE snapshot',
        );
      final asOf = _rocDate(match['Date']);
      final price = _positiveDecimal(match['ClosingPrice']);
      if (price == null)
        return const MarketResult(
          MarketState.missing,
          reason: 'TWSE has no closing trade price for this symbol',
        );
      final quote = StockClose(
        symbol: instrument.symbol,
        decimalPrice: price,
        asOf: asOf,
        fetchedAt: fetched.snapshot!.fetchedAt,
      );
      final stale =
          fetched.state == MarketState.stale || _isStale(asOf, requiredAsOf);
      return MarketResult(
        stale ? MarketState.stale : MarketState.available,
        value: quote,
        reason: stale
            ? fetched.reason ?? 'Observation is older than requested'
            : null,
      );
    } on FormatException {
      return const MarketResult(
        MarketState.failed,
        reason: 'Invalid TWSE response',
      );
    }
  }

  /// ECB publishes EUR-base reference rates. Supported quote currencies are
  /// intentionally explicit; no cross-rate or non-ECB source is synthesized.
  Future<MarketResult<ReferenceRate>> fxRate(
    Currency base,
    Currency quote, {
    BusinessDate? requiredAsOf,
  }) async {
    const supported = {'USD', 'JPY', 'GBP', 'CHF'};
    final direct = base.code == 'EUR' && supported.contains(quote.code);
    final inverse = quote.code == 'EUR' && supported.contains(base.code);
    if ((!direct && !inverse) ||
        !_validCurrency(base) ||
        !_validCurrency(quote)) {
      return const MarketResult(
        MarketState.unsupported,
        reason: 'ECB route supports EUR against USD, JPY, GBP or CHF',
      );
    }
    final currency = direct ? quote.code : base.code;
    final params = <String, String>{'format': 'csvdata', 'detail': 'dataonly'};
    if (requiredAsOf == null) {
      params['lastNObservations'] = '1';
    } else {
      params['startPeriod'] = requiredAsOf.toString();
      params['endPeriod'] = requiredAsOf.toString();
    }
    final uri = Uri.https(
      'data-api.ecb.europa.eu',
      '/service/data/EXR/D.$currency.EUR.SP00.A',
      params,
    );
    final fetched = await _fetch(uri);
    if (fetched.snapshot == null) {
      return MarketResult(fetched.state, reason: fetched.reason);
    }
    try {
      final rows = _ecbRows(fetched.snapshot!.body, currency);
      if (rows.isEmpty)
        return const MarketResult(
          MarketState.missing,
          reason: 'ECB returned no observation',
        );
      if (rows.length != 1)
        throw const FormatException('Multiple ECB observations');
      final asOf = rows.single.asOf;
      final decimal = rows.single.decimal;
      if (decimal == null)
        return const MarketResult(
          MarketState.missing,
          reason: 'ECB has no numeric reference rate',
        );
      if (requiredAsOf != null && asOf != requiredAsOf) {
        return const MarketResult(
          MarketState.missing,
          reason: 'ECB has no rate on the requested date',
        );
      }
      final eur = Currency('EUR', 2);
      final foreign = Currency(currency, currency == 'JPY' ? 0 : 2);
      final published = FxRate.parse(eur, foreign, decimal);
      final observation = FxObservation(
        rate: inverse ? published.inverse() : published,
        source: ReferenceRate.provider,
        asOf: asOf,
        retrievedAt: fetched.snapshot!.fetchedAt,
      );
      final stale =
          fetched.state == MarketState.stale || _isStale(asOf, requiredAsOf);
      return MarketResult(
        stale ? MarketState.stale : MarketState.available,
        value: ReferenceRate(observation: observation, derivedInverse: inverse),
        reason: stale
            ? fetched.reason ?? 'Observation is older than requested'
            : null,
      );
    } on FormatException {
      return const MarketResult(
        MarketState.failed,
        reason: 'Invalid ECB response',
      );
    } on FxException {
      return const MarketResult(MarketState.failed, reason: 'Invalid ECB rate');
    }
  }

  bool _isStale(BusinessDate asOf, BusinessDate? requiredAsOf) {
    if (requiredAsOf != null) return asOf != requiredAsOf;
    final date = DateTime.utc(asOf.year, asOf.month, asOf.day);
    final today = _clock().toUtc();
    final todayDate = DateTime.utc(today.year, today.month, today.day);
    final age = todayDate.difference(date);
    return age.isNegative || age > maximumObservationAge;
  }

  Future<_Fetch> _fetch(Uri uri) {
    final now = _clock().toUtc();
    final cached = _cache[uri];
    if (cached != null &&
        !now.isBefore(cached.fetchedAt.value) &&
        now.difference(cached.fetchedAt.value) < cacheTtl) {
      return Future.value(_Fetch(cached, MarketState.available));
    }
    final inFlight = _pending[uri];
    if (inFlight != null) return inFlight;
    final last = _lastAttempt[uri.host];
    if (last != null &&
        !now.isBefore(last) &&
        now.difference(last) < requestCooldown) {
      return Future.value(
        _Fetch(
          cached,
          cached == null ? MarketState.throttled : MarketState.stale,
          'Request cooldown is active',
        ),
      );
    }
    _lastAttempt[uri.host] = now;
    final future = _request(uri, cached, UtcInstant(now));
    _pending[uri] = future;
    return future.whenComplete(() => _pending.remove(uri));
  }

  Future<_Fetch> _request(Uri uri, _Snapshot? prior, UtcInstant now) async {
    try {
      final response = await _transport.get(uri);
      if (response.statusCode == 404 || response.statusCode == 204) {
        return const _Fetch(
          null,
          MarketState.missing,
          'Provider has no observation',
        );
      }
      if (response.statusCode == 429) {
        return _Fetch(
          prior,
          prior == null ? MarketState.throttled : MarketState.stale,
          'Provider rate limit',
        );
      }
      if (response.statusCode != 200 ||
          response.body.length > 2 * 1024 * 1024) {
        return _Fetch(
          prior,
          prior == null ? MarketState.failed : MarketState.stale,
          'Provider request failed',
        );
      }
      final snapshot = _Snapshot(response.body, now);
      _cache[uri] = snapshot;
      if (_cache.length > 32) _cache.remove(_cache.keys.first);
      return _Fetch(snapshot, MarketState.available);
    } catch (_) {
      return _Fetch(
        prior,
        prior == null ? MarketState.failed : MarketState.stale,
        'Provider request failed',
      );
    }
  }

  /// Historical ECB reference rate for [date]. A prior observation within a
  /// bounded window is returned as stale, never as the requested day's rate.
  /// This supports weekends/holidays without fabricating a published quote.
  Future<MarketResult<ReferenceRate>> historicalFxRate(
    Currency base,
    Currency quote, {
    required BusinessDate date,
    int lookbackDays = 7,
  }) async {
    if (lookbackDays < 0 || lookbackDays > 7) {
      throw RangeError.range(lookbackDays, 0, 7, 'lookbackDays');
    }
    const supported = {'USD', 'JPY', 'GBP', 'CHF'};
    final direct = base.code == 'EUR' && supported.contains(quote.code);
    final inverse = quote.code == 'EUR' && supported.contains(base.code);
    if ((!direct && !inverse) ||
        !_validCurrency(base) ||
        !_validCurrency(quote)) {
      return const MarketResult(
        MarketState.unsupported,
        reason: 'ECB route supports EUR against USD, JPY, GBP or CHF',
      );
    }
    final currency = direct ? quote.code : base.code;
    final requested = DateTime.utc(date.year, date.month, date.day);
    final first = requested.subtract(Duration(days: lookbackDays));
    if (first.year < 1) {
      throw RangeError('Historical lookup precedes supported calendar');
    }
    final start = BusinessDate(first.year, first.month, first.day);
    final uri = Uri.https(
      'data-api.ecb.europa.eu',
      '/service/data/EXR/D.$currency.EUR.SP00.A',
      {
        'format': 'csvdata',
        'detail': 'dataonly',
        'startPeriod': start.toString(),
        'endPeriod': date.toString(),
      },
    );
    final fetched = await _fetch(uri);
    if (fetched.snapshot == null) {
      return MarketResult(fetched.state, reason: fetched.reason);
    }
    try {
      final rows = _ecbRows(fetched.snapshot!.body, currency);
      _EcbRow? chosen;
      for (final row in rows) {
        if (row.asOf.compareTo(start) < 0 || row.asOf.compareTo(date) > 0) {
          throw const FormatException(
            'ECB observation outside requested range',
          );
        }
        if (row.decimal != null &&
            (chosen == null || row.asOf.compareTo(chosen.asOf) > 0)) {
          chosen = row;
        }
      }
      if (chosen == null) {
        return const MarketResult(
          MarketState.missing,
          reason: 'ECB has no rate within the historical window',
        );
      }
      final eur = Currency('EUR', 2);
      final foreign = Currency(currency, currency == 'JPY' ? 0 : 2);
      final published = FxRate.parse(eur, foreign, chosen.decimal!);
      final observation = FxObservation(
        rate: inverse ? published.inverse() : published,
        source: ReferenceRate.provider,
        asOf: chosen.asOf,
        retrievedAt: fetched.snapshot!.fetchedAt,
      );
      final stale = fetched.state == MarketState.stale || chosen.asOf != date;
      return MarketResult(
        stale ? MarketState.stale : MarketState.available,
        value: ReferenceRate(observation: observation, derivedInverse: inverse),
        reason: stale
            ? fetched.reason ?? 'ECB observation predates requested date'
            : null,
      );
    } on FormatException {
      return const MarketResult(
        MarketState.failed,
        reason: 'Invalid ECB response',
      );
    } on FxException {
      return const MarketResult(MarketState.failed, reason: 'Invalid ECB rate');
    }
  }
}

bool _twseSymbolSupported(InvestmentInstrument instrument) {
  final symbol = instrument.symbol;
  return switch (instrument.kind) {
    InstrumentKind.stock => RegExp(r'^[1-9][0-9]{3}$').hasMatch(symbol),
    InstrumentKind.etf => RegExp(r'^00[0-9]{2,4}$').hasMatch(symbol),
  };
}

bool _validCurrency(Currency c) => c.scale == (c.code == 'JPY' ? 0 : 2);

BusinessDate _rocDate(Object? value) {
  if (value is! String || !RegExp(r'^[0-9]{7}$').hasMatch(value)) {
    throw const FormatException('Invalid ROC date');
  }
  final year = int.parse(value.substring(0, 3)) + 1911;
  return BusinessDate(
    year,
    int.parse(value.substring(3, 5)),
    int.parse(value.substring(5, 7)),
  );
}

String? _positiveDecimal(Object? value) {
  if (value is! String) throw const FormatException('Expected decimal text');
  final text = value.trim();
  if (text.isEmpty || text == '--' || text == 'X') return null;
  if (text.length > 128 ||
      !RegExp(r'^(?:[0-9]+|[1-9][0-9]{0,2}(?:,[0-9]{3})+)(\.[0-9]{1,12})?$')
          .hasMatch(text)) {
    throw const FormatException('Invalid decimal');
  }
  final clean = text.replaceAll(',', '');
  final parts = clean.split('.');
  if (BigInt.parse(parts.join()) <= BigInt.zero) return null;
  return clean;
}

List<_EcbRow> _ecbRows(String body, String currency) {
  final rows = _csvRows(body);
  if (rows.isEmpty) return const [];
  final headers = rows.first;
  final indexes = <String, int>{};
  for (var i = 0; i < headers.length; i++) {
    if (indexes.containsKey(headers[i])) {
      throw const FormatException('Duplicate ECB column');
    }
    indexes[headers[i]] = i;
  }
  for (final key in [
    'FREQ',
    'CURRENCY',
    'CURRENCY_DENOM',
    'EXR_TYPE',
    'EXR_SUFFIX',
    'TIME_PERIOD',
    'OBS_VALUE',
  ]) {
    if (!indexes.containsKey(key)) {
      throw const FormatException('ECB column missing');
    }
  }
  final observations = <_EcbRow>[];
  final dates = <BusinessDate>{};
  for (final row in rows.skip(1)) {
    if (row.length != headers.length ||
        row[indexes['FREQ']!] != 'D' ||
        row[indexes['CURRENCY']!] != currency ||
        row[indexes['CURRENCY_DENOM']!] != 'EUR' ||
        row[indexes['EXR_TYPE']!] != 'SP00' ||
        row[indexes['EXR_SUFFIX']!] != 'A') {
      throw const FormatException('Wrong ECB series');
    }
    final date = BusinessDate.parse(row[indexes['TIME_PERIOD']!]);
    if (!dates.add(date)) throw const FormatException('Duplicate ECB date');
    observations.add(
      _EcbRow(date, _positiveDecimal(row[indexes['OBS_VALUE']!])),
    );
  }
  return observations;
}

List<List<String>> _csvRows(String input) {
  final result = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (ch == '"') {
      if (quoted && i + 1 < input.length && input[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == ',' && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if ((ch == '\n' || ch == '\r') && !quoted) {
      if (ch == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
      row.add(field.toString());
      field = StringBuffer();
      if (row.any((cell) => cell.isNotEmpty)) result.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  if (quoted) throw const FormatException('Unclosed CSV quote');
  if (row.isNotEmpty || field.isNotEmpty) {
    row.add(field.toString());
    if (row.any((cell) => cell.isNotEmpty)) result.add(row);
  }
  return result;
}
