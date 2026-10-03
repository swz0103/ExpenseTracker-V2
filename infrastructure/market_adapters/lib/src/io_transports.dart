import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:market_data/market_data.dart';

/// Android/desktop transport with a finite response budget and no redirects.
final class IoMarketTransport implements MarketTransport {
  const IoMarketTransport();

  static const maximumResponseBytes = marketResponseLimit;

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
        if (bytes.length > maximumResponseBytes) {
          throw const FormatException('Market response too large');
        }
      }
      return MarketResponse(response.statusCode, utf8.decode(bytes));
    } finally {
      client.close(force: true);
    }
  }
}

final class IoFugleMarketTransport implements FugleMarketTransport {
  const IoFugleMarketTransport();

  static const maximumResponseBytes = fugleResponseLimit;

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

final class IoTwelveDataTransport implements TwelveDataTransport {
  const IoTwelveDataTransport();

  static const maximumResponseBytes = twelveDataResponseLimit;

  @override
  Future<MarketResponse> get(Uri uri, {required String apiKey}) async {
    if (uri.scheme != 'https' ||
        uri.host != 'api.twelvedata.com' ||
        uri.path != '/time_series') {
      throw ArgumentError('Untrusted Twelve Data URI');
    }
    _validateKey(apiKey);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'ExpenseTracker-V2');
      request.headers.set(HttpHeaders.authorizationHeader, 'apikey $apiKey');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        bytes.addAll(chunk);
        if (bytes.length > maximumResponseBytes) {
          throw const FormatException('Twelve Data response too large');
        }
      }
      return MarketResponse(response.statusCode, utf8.decode(bytes));
    } finally {
      client.close(force: true);
    }
  }
}

final class IoYahooChartTransport implements YahooChartTransport {
  const IoYahooChartTransport();

  static const maximumResponseBytes = yahooChartResponseLimit;

  @override
  Future<MarketResponse> get(Uri uri) async {
    if (uri.scheme != 'https' ||
        uri.host != 'query1.finance.yahoo.com' ||
        !uri.path.startsWith('/v8/finance/chart/')) {
      throw ArgumentError('Untrusted Yahoo Chart URI');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'ExpenseTracker-V2');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        bytes.addAll(chunk);
        if (bytes.length > maximumResponseBytes) {
          throw const FormatException('Yahoo Chart response too large');
        }
      }
      return MarketResponse(response.statusCode, utf8.decode(bytes));
    } finally {
      client.close(force: true);
    }
  }
}
