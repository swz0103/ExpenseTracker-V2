import 'dart:io';

import 'package:market/market_data.dart';

import 'platform_channel.dart';
import '../../core/time/app_clock.dart';
import '../../core/diagnostics/error_log.dart';
import '../../core/diagnostics/error_steps.dart';

/// The exchanges' day lists and the bank's rates as Android's background
/// job last fetched them (`MarketWorker.kt`), so the closes are there
/// when the app opens rather than a few MiB later. A list still fresh is
/// read from [dir]; otherwise [inner] asks the network, and what it
/// brings is kept there too. Other addresses always go to the network.
final class CachedMarketTransport implements MarketTransport {
  CachedMarketTransport(this.inner, this.dir, {DateTime Function()? clock})
    : _clock = clock ?? AppClock.now;

  final MarketTransport inner;
  final Directory dir;
  final DateTime Function() _clock;

  /// The addresses kept, by the name of the file each is kept in, which
  /// the background job fetches.
  static final kept = {
    _twse: MarketDataGateway.twseUri,
    _tpex: MarketDataGateway.tpexUri,
    rateBoard: MarketDataGateway.bankRatesUri,
  };

  static const _twse = 'twse';
  static const _tpex = 'tpex';

  /// The day lists of the exchanges, by the names in [kept].
  static const stockLists = {_twse, _tpex};

  /// The bank's board, by its name in [kept].
  static const rateBoard = 'rates';

  /// How long a day list is kept at most: the last close stays the
  /// latest until the next.
  static const stockMaxAge = Duration(hours: 12);

  /// How long the bank's rates are kept: they move through the day.
  static const rateMaxAge = Duration(hours: 3);

  /// The exchanges' close, 14:30 in Taipei, as hour and minute in UTC.
  static const _closeHourUtc = 6;
  static const _closeMinuteUtc = 30;

  /// How many closes, from the last one on, the background job is told
  /// of each time the list is written: a week and a day, so it keeps
  /// the closes coming while the app stays closed that long.
  static const toldCloses = 8;

  /// The job's half-written copy is `.worker.part` (`MarketWorker.kt`);
  /// the app's has its own name, so the two never write into one file.
  static const _partSuffix = '.app.part';

  /// The close of the Taipei day [taipei] (a time shifted to Taipei's
  /// clock), [days] later.
  static DateTime _close(DateTime taipei, [int days = 0]) => DateTime.utc(
    taipei.year,
    taipei.month,
    taipei.day + days,
    _closeHourUtc,
    _closeMinuteUtc,
  );

  /// The last close at or before [now], then the next ones: in all
  /// [toldCloses].
  static List<DateTime> closesFrom(DateTime now) {
    final utc = now.toUtc();
    final taipei = utc.add(const Duration(hours: 8));
    final first = utc.isBefore(_close(taipei)) ? -1 : 0;
    return [for (var i = 0; i < toldCloses; i++) _close(taipei, first + i)];
  }

  /// Tells the background job what to fetch, a line each, tabs between:
  /// a name, an address, and when its kept copy goes stale by [fresh]'s
  /// rule: its most age in milliseconds, and the closes (as instants in
  /// milliseconds, commas between) a copy kept before goes stale at; the
  /// job only compares (`MarketWorker.kt`). The exchanges' day lists only
  /// while [stocks] are held, the bank's rates only while an account is
  /// kept in another currency ([rates]); nothing for a ledger that needs
  /// neither (AND-05). True when there is anything to fetch.
  Future<bool> writeList({required bool stocks, required bool rates}) async {
    final wanted = {if (stocks) ...stockLists, if (rates) rateBoard};
    final closes = [
      for (final close in closesFrom(_clock())) close.millisecondsSinceEpoch,
    ].join(',');
    await dir.create(recursive: true);
    await File('${dir.path}/urls.txt').writeAsString(
      [
        for (final MapEntry(:key, :value) in kept.entries)
          if (wanted.contains(key))
            key == rateBoard
                ? '$key\t$value\t${rateMaxAge.inMilliseconds}\t'
                : '$key\t$value\t${stockMaxAge.inMilliseconds}\t$closes',
      ].join('\n'),
    );
    return wanted.isNotEmpty;
  }

  /// The file [uri] is kept in, the one the background job writes; null
  /// for an address not kept.
  File? fileOf(Uri uri) {
    for (final MapEntry(:key, :value) in kept.entries) {
      if (value == uri) return File('${dir.path}/$key.txt');
    }
    return null;
  }

  /// Whether a list fetched at [at] still holds the latest close: fetched
  /// within [stockMaxAge], and after today's close (about 14:30 in
  /// Taipei) once that has passed. The bank's rates move through the day,
  /// so they are kept [rateMaxAge].
  bool fresh(Uri uri, DateTime at) {
    final now = _clock();
    final age = now.difference(at);
    if (age.isNegative) return false;
    if (uri == MarketDataGateway.bankRatesUri) return age < rateMaxAge;
    if (age >= stockMaxAge) return false;
    final close = _close(now.toUtc().add(const Duration(hours: 8)));
    return now.toUtc().isBefore(close) || !at.toUtc().isBefore(close);
  }

  @override
  Future<MarketResponse> get(Uri uri) async {
    final file = fileOf(uri);
    if (file == null) return inner.get(uri);
    try {
      if (file.existsSync() && fresh(uri, file.lastModifiedSync())) {
        return MarketResponse(200, await file.readAsString());
      }
    } on FileSystemException catch (error) {
      // Read from the network instead.
      ErrorLog.instance.record(ErrorSteps.marketCache, error);
    }
    final response = await inner.get(uri);
    if (response.statusCode == 200) {
      try {
        await dir.create(recursive: true);
        final partial = File('${file.path}$_partSuffix');
        await partial.writeAsString(response.body);
        await partial.rename(file.path);
      } on FileSystemException catch (error) {
        // Kept next time.
        ErrorLog.instance.record(ErrorSteps.marketCache, error);
      }
    }
    return response;
  }
}

/// Starts the background job that fetches the lists of `urls.txt`
/// (`MarketWorker.kt`), or stops it with `on: false`.
Future<void> androidMarketJob({required bool on}) =>
    platformChannel.invokeMethod<void>('marketJob', {'on': on});
