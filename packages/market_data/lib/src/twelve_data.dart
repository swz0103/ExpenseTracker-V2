import 'dart:async';
import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';

import 'intraday.dart';
import 'market_data.dart';

abstract interface class TwelveDataTransport {
  Future<MarketResponse> get(Uri uri, {required String apiKey});
}

/// Largest response body accepted from this provider, in bytes.
const twelveDataResponseLimit = 1024 * 1024;

typedef TwelveDataApiKeySource = Future<String> Function();

final class TwelveDataIntradayGateway {
  TwelveDataIntradayGateway({
    required TwelveDataApiKeySource apiKeySource,
    required TwelveDataTransport transport,
    DateTime Function()? clock,
  }) : _apiKeySource = apiKeySource,
       _transport = transport,
       _clock = clock ?? DateTime.now;

  final TwelveDataApiKeySource _apiKeySource;
  final TwelveDataTransport _transport;
  final DateTime Function() _clock;
  final Map<String, Future<MarketResult<IntradayBar>>> _pending = {};

  Future<MarketResult<IntradayBar>> latestBar(
    InvestmentInstrument instrument, {
    required IntradayInterval interval,
  }) {
    if (!supportsTwelveDataInstrument(instrument)) {
      return Future.value(
        const MarketResult(
          MarketState.unsupported,
          reason: 'Twelve Data route supports selected USD US exchanges',
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
      _validateKey(apiKey);
      final uri = Uri.https('api.twelvedata.com', '/time_series', {
        'symbol': instrument.symbol,
        'interval': '${interval.minutes}min',
        'outputsize': '2',
        'timezone': 'UTC',
        'format': 'JSON',
      });
      final response = await _transport.get(uri, apiKey: apiKey);
      if (response.statusCode == 401 || response.statusCode == 403) {
        return const MarketResult(
          MarketState.failed,
          reason: 'Twelve Data authorization is required or insufficient',
        );
      }
      if (response.statusCode == 404 || response.statusCode == 204) {
        return const MarketResult(
          MarketState.missing,
          reason: 'Twelve Data has no intraday observation',
        );
      }
      if (response.statusCode == 429) {
        return const MarketResult(
          MarketState.throttled,
          reason: 'Twelve Data request limit reached',
        );
      }
      if (response.statusCode != 200 ||
          response.body.length > twelveDataResponseLimit) {
        return const MarketResult(
          MarketState.failed,
          reason: 'Twelve Data request failed',
        );
      }
      return _parse(response.body, instrument, interval);
    } on FormatException {
      return const MarketResult(
        MarketState.failed,
        reason: 'Invalid Twelve Data response',
      );
    } on ArgumentError {
      return const MarketResult(
        MarketState.failed,
        reason: 'Twelve Data credential is unavailable or invalid',
      );
    } catch (_) {
      return const MarketResult(
        MarketState.failed,
        reason: 'Twelve Data request failed',
      );
    }
  }

  MarketResult<IntradayBar> _parse(
    String body,
    InvestmentInstrument instrument,
    IntradayInterval interval,
  ) {
    final raw = jsonDecode(body);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid Twelve Data root');
    }
    if (raw['status'] == 'error') {
      final code = raw['code'];
      if (code == 429) {
        return const MarketResult(
          MarketState.throttled,
          reason: 'Twelve Data request limit reached',
        );
      }
      if (code == 404) {
        return const MarketResult(
          MarketState.missing,
          reason: 'Twelve Data has no intraday observation',
        );
      }
      return const MarketResult(
        MarketState.failed,
        reason: 'Twelve Data rejected the request',
      );
    }
    final meta = raw['meta'];
    if (meta is! Map<String, dynamic> ||
        meta['symbol'] != instrument.symbol ||
        meta['interval'] != '${interval.minutes}min' ||
        meta['currency'] != 'USD' ||
        meta['mic_code'] != instrument.marketCode) {
      throw const FormatException('Wrong Twelve Data series');
    }
    final values = raw['values'];
    if (values is! List) throw const FormatException('Invalid bars');
    if (values.isEmpty) {
      return const MarketResult(
        MarketState.missing,
        reason: 'Twelve Data has no intraday observation',
      );
    }
    final now = _clock().toUtc();
    _TwelveBar? latest;
    final timestamps = <DateTime>{};
    for (final item in values) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid bar');
      }
      final parsed = _parseBar(item);
      if (!timestamps.add(parsed.observed)) {
        throw const FormatException('Duplicate bar');
      }
      if (parsed.observed.isAfter(now.add(const Duration(minutes: 1)))) {
        throw const FormatException('Future bar');
      }
      if (latest == null || parsed.observed.isAfter(latest.observed)) {
        latest = parsed;
      }
    }
    if (latest == null) throw const FormatException('Missing bar');
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
    final stale =
        now.difference(latest.observed) >
        interval.duration + const Duration(minutes: 1);
    return MarketResult(
      stale ? MarketState.stale : MarketState.available,
      value: bar,
      reason: stale ? 'Intraday observation is older than its cadence' : null,
    );
  }
}

bool supportsTwelveDataInstrument(InvestmentInstrument instrument) =>
    const {'XNAS', 'XNYS', 'ARCX'}.contains(instrument.marketCode) &&
    instrument.tradingCurrency == Currency('USD', 2) &&
    RegExp(r'^[A-Z][A-Z0-9.-]{0,9}$').hasMatch(instrument.symbol);

final class _TwelveBar {
  const _TwelveBar({
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

_TwelveBar _parseBar(Map<String, dynamic> raw) {
  final observed = _utcTimestamp(raw['datetime']);
  final open = _decimal(raw['open']);
  final high = _decimal(raw['high']);
  final low = _decimal(raw['low']);
  final close = _decimal(raw['close']);
  if (_compare(low, high) > 0 ||
      _compare(open, low) < 0 ||
      _compare(open, high) > 0 ||
      _compare(close, low) < 0 ||
      _compare(close, high) > 0) {
    throw const FormatException('Invalid OHLC range');
  }
  final volume = raw['volume'];
  if (volume is! String || !RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(volume)) {
    throw const FormatException('Invalid volume');
  }
  return _TwelveBar(
    observed: observed,
    open: open,
    high: high,
    low: low,
    close: close,
    volume: BigInt.parse(volume),
  );
}

DateTime _utcTimestamp(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid UTC timestamp');
  }
  return DateTime.parse('${value.replaceFirst(' ', 'T')}Z');
}

String _decimal(Object? value) {
  if (value is! String ||
      !RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,12})?$').hasMatch(value) ||
      BigInt.parse(value.replaceAll('.', '')) <= BigInt.zero) {
    throw const FormatException('Invalid decimal');
  }
  return value;
}

int _compare(String left, String right) {
  final a = left.split('.');
  final b = right.split('.');
  final aScale = a.length == 2 ? a[1].length : 0;
  final bScale = b.length == 2 ? b[1].length : 0;
  final scale = aScale > bScale ? aScale : bScale;
  BigInt scaled(List<String> value) {
    final fraction = value.length == 2 ? value[1] : '';
    return BigInt.parse(
      '${value[0]}$fraction${'0' * (scale - fraction.length)}',
    );
  }

  return scaled(a).compareTo(scaled(b));
}

void _validateKey(String value) {
  if (value.isEmpty ||
      value.length > 512 ||
      !RegExp(r'^[\x21-\x7E]+$').hasMatch(value)) {
    throw ArgumentError('Invalid Twelve Data API key');
  }
}
