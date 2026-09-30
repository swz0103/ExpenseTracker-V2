import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';

import 'market_data.dart';

enum IntradayInterval {
  oneMinute(1),
  fiveMinutes(5);

  const IntradayInterval(this.minutes);
  final int minutes;
  Duration get duration => Duration(minutes: minutes);
}

final class IntradayBar {
  const IntradayBar({
    required this.symbol,
    required this.interval,
    required this.startsAt,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.fetchedAt,
  });

  final String symbol;
  final IntradayInterval interval;
  final UtcInstant startsAt;
  final String open;
  final String high;
  final String low;
  final String close;
  final BigInt volume;
  final UtcInstant fetchedAt;
}

abstract interface class FugleMarketTransport {
  Future<MarketResponse> get(Uri uri, {required String apiKey});
}

final class IoFugleMarketTransport implements FugleMarketTransport {
  const IoFugleMarketTransport();

  static const maximumResponseBytes = 1024 * 1024;

  @override
  Future<MarketResponse> get(Uri uri, {required String apiKey}) async {
    if (uri.scheme != 'https' ||
        uri.host != 'api.fugle.tw' ||
        !uri.path.startsWith('/marketdata/v1.0/stock/')) {
      throw ArgumentError('Untrusted Fugle URI');
    }
    _validateApiKey(apiKey);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'ExpenseTracker-V2');
      request.headers.set('X-API-KEY', apiKey);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        bytes.addAll(chunk);
        if (bytes.length > maximumResponseBytes) {
          throw const FormatException('Fugle response too large');
        }
      }
      return MarketResponse(response.statusCode, utf8.decode(bytes));
    } finally {
      client.close(force: true);
    }
  }
}

typedef FugleApiKeySource = Future<String> Function();

final class FugleIntradayGateway {
  FugleIntradayGateway({
    required FugleApiKeySource apiKeySource,
    FugleMarketTransport? transport,
    DateTime Function()? clock,
  }) : _apiKeySource = apiKeySource,
       _transport = transport ?? const IoFugleMarketTransport(),
       _clock = clock ?? DateTime.now;

  final FugleApiKeySource _apiKeySource;
  final FugleMarketTransport _transport;
  final DateTime Function() _clock;
  final Map<String, Future<MarketResult<IntradayBar>>> _pending = {};

  Future<MarketResult<IntradayBar>> latestBar(
    InvestmentInstrument instrument, {
    required IntradayInterval interval,
  }) {
    if (!_supports(instrument)) {
      return Future.value(
        const MarketResult(
          MarketState.unsupported,
          reason: 'Fugle intraday supports TWSE and TPEx TWD stocks or ETFs',
        ),
      );
    }
    final key =
        '${instrument.marketCode}:${instrument.symbol}:${interval.name}';
    final active = _pending[key];
    if (active != null) return active;
    final future = _request(instrument, interval);
    _pending[key] = future;
    return future.whenComplete(() => _pending.remove(key));
  }

  Future<MarketResult<IntradayBar>> _request(
    InvestmentInstrument instrument,
    IntradayInterval interval,
  ) async {
    try {
      final apiKey = await _apiKeySource();
      _validateApiKey(apiKey);
      final uri = Uri.https(
        'api.fugle.tw',
        '/marketdata/v1.0/stock/intraday/candles/${instrument.symbol}',
        {'timeframe': '${interval.minutes}', 'sort': 'desc'},
      );
      final response = await _transport.get(uri, apiKey: apiKey);
      if (response.statusCode == 401 || response.statusCode == 403) {
        return const MarketResult(
          MarketState.failed,
          reason: 'Fugle authorization is required or insufficient',
        );
      }
      if (response.statusCode == 404 || response.statusCode == 204) {
        return const MarketResult(
          MarketState.missing,
          reason: 'Fugle has no intraday observation',
        );
      }
      if (response.statusCode == 429) {
        return const MarketResult(
          MarketState.throttled,
          reason: 'Fugle request limit reached',
        );
      }
      if (response.statusCode != 200 ||
          response.body.length > IoFugleMarketTransport.maximumResponseBytes) {
        return const MarketResult(
          MarketState.failed,
          reason: 'Fugle request failed',
        );
      }
      return _parse(response.body, instrument, interval);
    } on FormatException {
      return const MarketResult(
        MarketState.failed,
        reason: 'Invalid Fugle response',
      );
    } on ArgumentError {
      return const MarketResult(
        MarketState.failed,
        reason: 'Fugle credential is unavailable or invalid',
      );
    } catch (_) {
      return const MarketResult(
        MarketState.failed,
        reason: 'Fugle request failed',
      );
    }
  }

  MarketResult<IntradayBar> _parse(
    String body,
    InvestmentInstrument instrument,
    IntradayInterval interval,
  ) {
    final raw = jsonDecode(body);
    if (raw is! Map<String, dynamic> ||
        raw['symbol'] != instrument.symbol ||
        raw['timeframe']?.toString() != '${interval.minutes}' ||
        raw['exchange'] != 'TWSE' ||
        raw['market'] != (instrument.marketCode == 'TWSE' ? 'TSE' : 'OTC')) {
      throw const FormatException('Wrong Fugle series');
    }
    final data = raw['data'];
    if (data is! List) throw const FormatException('Invalid Fugle bars');
    if (data.isEmpty) {
      return const MarketResult(
        MarketState.missing,
        reason: 'Fugle has no intraday observation',
      );
    }
    final now = _clock().toUtc();
    _ParsedBar? latest;
    final timestamps = <DateTime>{};
    for (final item in data) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid Fugle bar');
      }
      final parsed = _parseBar(item);
      if (!timestamps.add(parsed.observed)) {
        throw const FormatException('Duplicate Fugle bar');
      }
      if (parsed.observed.isAfter(now.add(const Duration(minutes: 1)))) {
        throw const FormatException('Future Fugle observation');
      }
      if (latest == null || parsed.observed.isAfter(latest.observed)) {
        latest = parsed;
      }
    }
    if (latest == null) throw const FormatException('Missing Fugle bar');
    final bar = IntradayBar(
      symbol: instrument.symbol,
      interval: interval,
      startsAt: UtcInstant(latest.observed),
      open: latest.open,
      high: latest.high,
      low: latest.low,
      close: latest.close,
      volume: latest.volume,
      fetchedAt: UtcInstant(now),
    );
    final age = now.difference(latest.observed);
    final stale = age > interval.duration + const Duration(minutes: 1);
    return MarketResult(
      stale ? MarketState.stale : MarketState.available,
      value: bar,
      reason: stale ? 'Intraday observation is older than its cadence' : null,
    );
  }
}

final class _ParsedBar {
  const _ParsedBar({
    required this.observed,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  final DateTime observed;
  final String open;
  final String high;
  final String low;
  final String close;
  final BigInt volume;
}

_ParsedBar _parseBar(Map<String, dynamic> raw) {
  final observed = DateTime.parse(_requiredString(raw['date'])).toUtc();
  final open = _price(raw['open']);
  final high = _price(raw['high']);
  final low = _price(raw['low']);
  final close = _price(raw['close']);
  if (_compareDecimal(low, high) > 0 ||
      _compareDecimal(open, low) < 0 ||
      _compareDecimal(open, high) > 0 ||
      _compareDecimal(close, low) < 0 ||
      _compareDecimal(close, high) > 0) {
    throw const FormatException('Invalid Fugle OHLC range');
  }
  return _ParsedBar(
    observed: observed,
    open: open,
    high: high,
    low: low,
    close: close,
    volume: _volume(raw['volume']),
  );
}

bool _supports(InvestmentInstrument instrument) {
  if (instrument.tradingCurrency != Currency('TWD', 2) ||
      (instrument.marketCode != 'TWSE' && instrument.marketCode != 'TPEX')) {
    return false;
  }
  return switch (instrument.kind) {
    InstrumentKind.stock => RegExp(
      r'^[1-9][0-9]{3}$',
    ).hasMatch(instrument.symbol),
    InstrumentKind.etf => RegExp(r'^00[0-9]{2,4}$').hasMatch(instrument.symbol),
  };
}

void _validateApiKey(String value) {
  if (value.isEmpty ||
      value.length > 512 ||
      !RegExp(r'^[\x21-\x7E]+$').hasMatch(value)) {
    throw ArgumentError('Invalid Fugle API key');
  }
}

String _requiredString(Object? value) {
  if (value is! String || value.isEmpty || value.length > 100) {
    throw const FormatException('Expected text');
  }
  return value;
}

String _price(Object? value) {
  if (value is! num && value is! String) {
    throw const FormatException('Expected price');
  }
  final text = value.toString();
  if (!RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,12})?$').hasMatch(text)) {
    throw const FormatException('Invalid price');
  }
  final digits = text.replaceAll('.', '');
  if (BigInt.parse(digits) <= BigInt.zero) {
    throw const FormatException('Non-positive price');
  }
  return text;
}

BigInt _volume(Object? value) {
  final text = value.toString();
  if (value is! int || !RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(text)) {
    throw const FormatException('Invalid volume');
  }
  return BigInt.parse(text);
}

int _compareDecimal(String left, String right) {
  final leftParts = left.split('.');
  final rightParts = right.split('.');
  final leftScale = leftParts.length == 2 ? leftParts[1].length : 0;
  final rightScale = rightParts.length == 2 ? rightParts[1].length : 0;
  final scale = leftScale > rightScale ? leftScale : rightScale;

  BigInt scaled(List<String> parts) {
    final fraction = parts.length == 2 ? parts[1] : '';
    return BigInt.parse(
      '${parts[0]}$fraction${'0' * (scale - fraction.length)}',
    );
  }

  return scaled(leftParts).compareTo(scaled(rightParts));
}
