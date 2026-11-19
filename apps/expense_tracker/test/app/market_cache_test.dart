import 'dart:io';

import 'package:expense_tracker/src/app/android/market_cache_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market/market_data.dart';

final class _Network implements MarketTransport {
  var asked = 0;

  @override
  Future<MarketResponse> get(Uri uri) async {
    asked++;
    return const MarketResponse(200, '[]');
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('market-cache-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'a day list fetched after today\'s close is read from the phone',
    () async {
      // 16:00 in Taipei.
      final now = DateTime.utc(2026, 11, 16, 8);
      final network = _Network();
      final cache = CachedMarketTransport(network, dir, clock: () => now);
      final file = cache.fileOf(MarketDataGateway.twseUri)!;
      file.writeAsStringSync('kept');
      file.setLastModifiedSync(DateTime.utc(2026, 11, 16, 7));
      final read = await cache.get(MarketDataGateway.twseUri);
      expect(read.body, 'kept');
      expect(network.asked, 0);
    },
  );

  test('one fetched before the close is asked again, and kept', () async {
    final now = DateTime.utc(2026, 11, 16, 8);
    final network = _Network();
    final cache = CachedMarketTransport(network, dir, clock: () => now);
    final file = cache.fileOf(MarketDataGateway.twseUri)!;
    file.writeAsStringSync('old');
    file.setLastModifiedSync(DateTime.utc(2026, 11, 16, 3));
    final read = await cache.get(MarketDataGateway.twseUri);
    expect(read.body, '[]');
    expect(network.asked, 1);
    expect(file.readAsStringSync(), '[]');
  });

  test('the list for the background job names each kept address', () async {
    final cache = CachedMarketTransport(_Network(), dir);
    await cache.writeList();
    final lines = File('${dir.path}/urls.txt').readAsLinesSync();
    expect(lines, hasLength(3));
    expect(lines.first, startsWith('twse\thttps://openapi.twse.com.tw/'));
  });
}
