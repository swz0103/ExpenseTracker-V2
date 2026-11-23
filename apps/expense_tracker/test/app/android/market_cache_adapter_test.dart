import 'dart:io';

import 'package:expense_tracker/src/app/android/market_cache_adapter.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
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

  test('a list that cannot be kept is still answered, and the fault is in '
      'the error log', () async {
    final network = _Network();
    // A file where the cache's folder should be: nothing can be kept.
    final blocked = File('${dir.path}/blocked')..writeAsStringSync('x');
    final cache = CachedMarketTransport(network, Directory(blocked.path));
    final before = ErrorLog.instance.count;
    final read = await cache.get(MarketDataGateway.twseUri);
    expect(read.body, '[]');
    expect(network.asked, 1);
    expect(ErrorLog.instance.count, greaterThan(before));
    expect(ErrorLog.instance.entries.first.$2, startsWith('行情快取：'));
  });

  test('the list for the background job names each kept address', () async {
    final cache = CachedMarketTransport(_Network(), dir);
    expect(await cache.writeList(stocks: true, rates: true), isTrue);
    final lines = File('${dir.path}/urls.txt').readAsLinesSync();
    expect(lines, hasLength(3));
    expect(lines.first, startsWith('twse\thttps://openapi.twse.com.tw/'));
  });

  test(
    'the background job fetches only what the ledger needs (AND-05)',
    () async {
      final cache = CachedMarketTransport(_Network(), dir);
      final list = File('${dir.path}/urls.txt');
      List<String> names() => [
        for (final line in list.readAsLinesSync()) line.split('\t').first,
      ];
      expect(await cache.writeList(stocks: true, rates: false), isTrue);
      expect(names(), ['twse', 'tpex']);
      expect(await cache.writeList(stocks: false, rates: true), isTrue);
      expect(names(), ['rates']);
      // No holdings and no foreign account: nothing, and the job is stopped.
      expect(await cache.writeList(stocks: false, rates: false), isFalse);
      expect(list.readAsStringSync(), isEmpty);
    },
  );
}
