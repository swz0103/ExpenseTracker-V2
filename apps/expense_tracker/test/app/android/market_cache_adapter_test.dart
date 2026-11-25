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

  test('each line tells the background job when its copy goes stale '
      '(review 21 finding 6)', () async {
    // 16:00 in Taipei, after the day's close.
    final now = DateTime.utc(2026, 11, 16, 8);
    final cache = CachedMarketTransport(_Network(), dir, clock: () => now);
    await cache.writeList(stocks: true, rates: true);
    final lines = File('${dir.path}/urls.txt').readAsLinesSync();
    // The day lists: 12 hours (12 * 3,600,000 = 43,200,000 ms) and eight
    // closes from today's, 2026-11-16 06:30 UTC = 1,794,810,600,000 ms, a
    // day (86,400,000 ms) apart, the last 2026-11-23 06:30 UTC =
    // 1,794,810,600,000 + 7 * 86,400,000 = 1,795,415,400,000.
    final twse = lines.first.split('\t');
    expect(twse[2], '43200000');
    final closes = twse[3].split(',');
    expect(closes, hasLength(8));
    expect(closes.first, '1794810600000');
    expect(closes[1], '1794897000000');
    expect(closes.last, '1795415400000');
    // The bank's rates: 3 hours (10,800,000 ms), no closes.
    expect(lines.last.split('\t').sublist(2), ['10800000', '']);
  });

  test('before the day\'s close the job is told of the one before', () {
    // 11:00 in Taipei: yesterday's close, 2026-11-15 06:30 UTC.
    final closes = CachedMarketTransport.closesFrom(
      DateTime.utc(2026, 11, 16, 3),
    );
    expect(closes.first, DateTime.utc(2026, 11, 15, 6, 30));
    // 01:00 in Taipei on the 17th is still before that day's close.
    expect(
      CachedMarketTransport.closesFrom(DateTime.utc(2026, 11, 16, 17)).first,
      DateTime.utc(2026, 11, 16, 6, 30),
    );
    // Exactly at the close: that close.
    expect(
      CachedMarketTransport.closesFrom(DateTime.utc(2026, 11, 16, 6, 30)).first,
      DateTime.utc(2026, 11, 16, 6, 30),
    );
  });

  test('the app keeps its half-written copy apart from the job\'s', () async {
    final now = DateTime.utc(2026, 11, 16, 8);
    final cache = CachedMarketTransport(_Network(), dir, clock: () => now);
    // The job's copy half written: the app neither reads nor overwrites it.
    final job = File('${dir.path}/twse.txt.worker.part')
      ..writeAsStringSync('half');
    await cache.get(MarketDataGateway.twseUri);
    expect(job.readAsStringSync(), 'half');
    expect(File('${dir.path}/twse.txt').readAsStringSync(), '[]');
    expect(File('${dir.path}/twse.txt.app.part').existsSync(), isFalse);
  });

  test('the kept ages are the ones the rule uses', () {
    final now = DateTime.utc(2026, 11, 16, 8);
    final cache = CachedMarketTransport(_Network(), dir, clock: () => now);
    // Rates: 2 h 59 min old is fresh, 3 h is not.
    expect(
      cache.fresh(
        MarketDataGateway.bankRatesUri,
        now.subtract(const Duration(hours: 2, minutes: 59)),
      ),
      isTrue,
    );
    expect(
      cache.fresh(
        MarketDataGateway.bankRatesUri,
        now.subtract(CachedMarketTransport.rateMaxAge),
      ),
      isFalse,
    );
    expect(CachedMarketTransport.stockMaxAge, const Duration(hours: 12));
  });
}
