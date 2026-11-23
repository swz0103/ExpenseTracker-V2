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

  /// Tells the background job what to fetch, a name and an address a
  /// line, a tab between: the exchanges' day lists only while [stocks]
  /// are held, the bank's rates only while an account is kept in
  /// another currency ([rates]); nothing for a ledger that needs neither
  /// (AND-05). True when there is anything to fetch.
  Future<bool> writeList({required bool stocks, required bool rates}) async {
    final wanted = {if (stocks) ...stockLists, if (rates) rateBoard};
    await dir.create(recursive: true);
    await File('${dir.path}/urls.txt').writeAsString(
      [
        for (final MapEntry(:key, :value) in kept.entries)
          if (wanted.contains(key)) '$key\t$value',
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
  /// in the last twelve hours, and after today's close (about 14:30 in
  /// Taipei) once that has passed. The bank's rates move through the day,
  /// so they are kept three hours.
  bool fresh(Uri uri, DateTime at) {
    final now = _clock();
    final age = now.difference(at);
    if (age.isNegative) return false;
    if (uri == MarketDataGateway.bankRatesUri) return age.inHours < 3;
    if (age.inHours >= 12) return false;
    final taipei = now.toUtc().add(const Duration(hours: 8));
    final close = DateTime.utc(taipei.year, taipei.month, taipei.day, 6, 30);
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
        final partial = File('${file.path}.part');
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
