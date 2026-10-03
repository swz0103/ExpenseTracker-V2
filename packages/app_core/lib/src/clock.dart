import 'package:foundation_values/foundation_values.dart';

/// The only source of "now" for application code, so tests control time
/// instead of racing the real clock.
abstract interface class Clock {
  UtcInstant now();
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  UtcInstant now() => UtcInstant(DateTime.now());
}

/// A clock that only moves when told to.
final class FixedClock implements Clock {
  FixedClock(this._now);

  UtcInstant _now;

  @override
  UtcInstant now() => _now;

  void advance(Duration duration) =>
      _now = UtcInstant(_now.value.add(duration));
}

/// The app keeps books on Taiwan time.
extension BusinessDay on Clock {
  /// Today in Taiwan (UTC+8, no daylight saving): the default date of new
  /// entries, so an entry made at 1 a.m. belongs to that day and month.
  BusinessDate today() {
    final taipei = now().value.toUtc().add(const Duration(hours: 8));
    return BusinessDate(taipei.year, taipei.month, taipei.day);
  }
}
