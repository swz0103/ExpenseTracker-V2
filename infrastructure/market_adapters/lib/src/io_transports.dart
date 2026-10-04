import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:market_data/market_data.dart';

/// Android and desktop transport: HTTPS to the three known hosts only, no
/// redirects, a ten-second budget per phase and a capped body.
final class IoMarketTransport implements MarketTransport {
  const IoMarketTransport();

  static final hosts = {
    MarketDataGateway.twseUri.host,
    MarketDataGateway.tpexUri.host,
    MarketDataGateway.bankRatesUri.host,
  };

  @override
  Future<MarketResponse> get(Uri uri) async {
    if (uri.scheme != 'https' || !hosts.contains(uri.host)) {
      throw ArgumentError.value(uri, 'uri', 'Not a market data host');
    }
    const timeout = Duration(seconds: 10);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      const accept = 'application/json, text/csv';
      request.headers.set(HttpHeaders.acceptHeader, accept);
      request.headers.set(HttpHeaders.userAgentHeader, 'ExpenseTracker-V2');
      final response = await request.close().timeout(timeout);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        bytes.add(chunk);
        if (bytes.length > marketResponseLimit) {
          throw const FormatException('Market response too large');
        }
      }
      return MarketResponse(
        response.statusCode,
        utf8.decode(bytes.takeBytes()),
      );
    } finally {
      client.close(force: true);
    }
  }
}
