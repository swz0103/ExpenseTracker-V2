import 'dart:async';
import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';

import 'intraday.dart';
import 'market_data.dart';

abstract interface class YahooChartTransport {
  Future<MarketResponse> get(Uri uri);
}

/// Largest response body accepted from this provider, in bytes.
const yahooChartResponseLimit = 1024 * 1024;

/// Best-effort adapter for Yahoo Finance's undocumented public chart endpoint.
///
/// It deliberately remains a separate provider so callers can display its
/// provenance and fall back when the endpoint changes, throttles or disappears.
final class YahooChartIntradayGateway {
  YahooChartIntradayGateway({
    required YahooChartTransport transport,
    DateTime Function()? clock,
  }) : _transport = transport,
       _clock = clock ?? DateTime.now;

  final YahooChartTransport _transport;
  final DateTime Function() _clock;
  final Map<String, Future<MarketResult<IntradayBar>>> _pending = {};

  bool supports(InvestmentInstrument instrument) =>
      _yahooSymbol(instrument) != null;

  Future<MarketResult<IntradayBar>> latestBar(
    InvestmentInstrument instrument, {
    required IntradayInterval interval,
  }) {
    final yahooSymbol = _yahooSymbol(instrument);
    if (yahooSymbol == null) {
      return Future.value(
        const MarketResult(
          MarketState.unsupported,
          reason: 'Yahoo Chart does not support this instrument mapping',
        ),
      );
    }
    final key = '$yahooSymbol:${interval.name}';
    final active = _pending[key];
    if (active != null) return active;
    final future = _request(instrument, yahooSymbol, interval);
    _pending[key] = future;
    return future.whenComplete(() => _pending.remove(key));
  }

  Future<MarketResult<IntradayBar>> _request(
    InvestmentInstrument instrument,
    String yahooSymbol,
    IntradayInterval interval,
  ) async {
    try {
      final uri = Uri.https(
        'query1.finance.yahoo.com',
        '/v8/finance/chart/$yahooSymbol',
        {
          'interval': interval == IntradayInterval.oneMinute ? '1m' : '5m',
          'range': '1d',
          'includePrePost': 'false',
          'events': 'none',
        },
      );
      final response = await _transport.get(uri);
      if (response.statusCode == 404 || response.statusCode == 204) {
        return const MarketResult(
          MarketState.missing,
          reason: 'Yahoo Chart has no intraday observation',
        );
      }
      if (response.statusCode == 429) {
        return const MarketResult(
          MarketState.throttled,
          reason: 'Yahoo Chart request limit reached',
        );
      }
      if (response.statusCode != 200 ||
          response.body.length > yahooChartResponseLimit) {
        return const MarketResult(
          MarketState.failed,
          reason: 'Yahoo Chart request failed',
        );
      }
      return _parse(response.body, instrument, yahooSymbol, interval);
    } on FormatException {
      return const MarketResult(
        MarketState.failed,
        reason: 'Invalid Yahoo Chart response',
      );
    } catch (_) {
      return const MarketResult(
        MarketState.failed,
        reason: 'Yahoo Chart request failed',
      );
    }
  }

  MarketResult<IntradayBar> _parse(
    String body,
    InvestmentInstrument instrument,
    String yahooSymbol,
    IntradayInterval interval,
  ) {
    final root = jsonDecode(body);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('Invalid Yahoo root');
    }
    final chart = root['chart'];
    if (chart is! Map<String, dynamic> || chart['error'] != null) {
      throw const FormatException('Invalid Yahoo chart');
    }
    final results = chart['result'];
    if (results is! List || results.length != 1) {
      throw const FormatException('Invalid Yahoo result');
    }
    final result = results.single;
    if (result is! Map<String, dynamic>) {
      throw const FormatException('Invalid Yahoo series');
    }
    final meta = result['meta'];
    if (meta is! Map<String, dynamic> ||
        meta['symbol'] != yahooSymbol ||
        meta['currency'] != instrument.tradingCurrency.code ||
        meta['dataGranularity'] !=
            (interval == IntradayInterval.oneMinute ? '1m' : '5m')) {
      throw const FormatException('Wrong Yahoo series');
    }
    final timestamps = result['timestamp'];
    final indicators = result['indicators'];
    if (timestamps is! List || indicators is! Map<String, dynamic>) {
      throw const FormatException('Invalid Yahoo observations');
    }
    final quotes = indicators['quote'];
    if (quotes is! List || quotes.length != 1) {
      throw const FormatException('Invalid Yahoo quote series');
    }
    final quote = quotes.single;
    if (quote is! Map<String, dynamic>) {
      throw const FormatException('Invalid Yahoo quote');
    }
    final opens = _series(quote['open'], timestamps.length);
    final highs = _series(quote['high'], timestamps.length);
    final lows = _series(quote['low'], timestamps.length);
    final closes = _series(quote['close'], timestamps.length);
    final volumes = _series(quote['volume'], timestamps.length);
    final now = _clock().toUtc();
    final seen = <int>{};
    _YahooBar? latest;
    for (var index = 0; index < timestamps.length; index++) {
      final rawTimestamp = timestamps[index];
      if (rawTimestamp is! int || !seen.add(rawTimestamp)) {
        throw const FormatException('Invalid Yahoo timestamp');
      }
      final observed = DateTime.fromMillisecondsSinceEpoch(
        rawTimestamp * 1000,
        isUtc: true,
      );
      if (observed.isAfter(now.add(const Duration(minutes: 1)))) {
        throw const FormatException('Future Yahoo observation');
      }
      if (opens[index] == null ||
          highs[index] == null ||
          lows[index] == null ||
          closes[index] == null ||
          volumes[index] == null) {
        continue;
      }
      final parsed = _YahooBar(
        observed: observed,
        open: _price(opens[index]),
        high: _price(highs[index]),
        low: _price(lows[index]),
        close: _price(closes[index]),
        volume: _volume(volumes[index]),
      );
      if (_compareDecimal(parsed.low, parsed.high) > 0 ||
          _compareDecimal(parsed.open, parsed.low) < 0 ||
          _compareDecimal(parsed.open, parsed.high) > 0 ||
          _compareDecimal(parsed.close, parsed.low) < 0 ||
          _compareDecimal(parsed.close, parsed.high) > 0) {
        throw const FormatException('Invalid Yahoo OHLC range');
      }
      if (latest == null || parsed.observed.isAfter(latest.observed)) {
        latest = parsed;
      }
    }
    if (latest == null) {
      return const MarketResult(
        MarketState.missing,
        reason: 'Yahoo Chart has no complete intraday observation',
      );
    }
    final age = now.difference(latest.observed);
    final stale = age > interval.duration + const Duration(minutes: 2);
    return MarketResult(
      stale ? MarketState.stale : MarketState.available,
      value: IntradayBar(
        symbol: instrument.symbol,
        interval: interval,
        startsAt: UtcInstant(latest.observed),
        open: latest.open,
        high: latest.high,
        low: latest.low,
        close: latest.close,
        volume: latest.volume,
        fetchedAt: UtcInstant(now),
      ),
      reason: stale ? 'Yahoo observation is older than its cadence' : null,
    );
  }
}

final class _YahooBar {
  const _YahooBar({
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

List<Object?> _series(Object? raw, int length) {
  if (raw is! List || raw.length != length) {
    throw const FormatException('Mismatched Yahoo series');
  }
  return raw;
}

String? _yahooSymbol(InvestmentInstrument instrument) {
  final currency = instrument.tradingCurrency;
  if (instrument.marketCode == 'TWSE' && currency == Currency.of('TWD')) {
    return '${instrument.symbol}.TW';
  }
  if (instrument.marketCode == 'TPEX' && currency == Currency.of('TWD')) {
    return '${instrument.symbol}.TWO';
  }
  if ({'XNAS', 'XNYS', 'ARCX'}.contains(instrument.marketCode) &&
      currency == Currency('USD', 2) &&
      RegExp(r'^[A-Z0-9][A-Z0-9.-]{0,23}$').hasMatch(instrument.symbol)) {
    return instrument.symbol;
  }
  return null;
}

String _price(Object? value) {
  if (value is! num && value is! String) {
    throw const FormatException('Expected Yahoo price');
  }
  final text = value.toString();
  if (!RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,12})?$').hasMatch(text)) {
    throw const FormatException('Invalid Yahoo price');
  }
  if (BigInt.parse(text.replaceAll('.', '')) <= BigInt.zero) {
    throw const FormatException('Non-positive Yahoo price');
  }
  return text;
}

BigInt _volume(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('Invalid Yahoo volume');
  }
  return BigInt.from(value);
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
