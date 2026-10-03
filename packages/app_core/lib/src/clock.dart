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
