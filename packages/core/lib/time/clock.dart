import 'calendar_day.dart';
import 'instant.dart';

/// The only source of "now" and "today". It enters the app at the
/// composition root and is handed down; pure code is given the day it
/// needs and never asks a clock.
///
/// "Today" is the calendar day in the phone's current time zone: the day
/// the person sees on their phone, wherever they are.
abstract interface class Clock {
  UtcInstant now();

  /// The calendar day it is now where the phone is.
  BusinessDate today();
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  UtcInstant now() => UtcInstant(DateTime.now());

  @override
  BusinessDate today() => BusinessDate.of(DateTime.now());
}

/// A clock that only moves when told to. Its zone is [offset] from UTC, so
/// a test gives the same day on any machine.
final class FixedClock implements Clock {
  FixedClock(this._now, {this.offset = Duration.zero});

  UtcInstant _now;

  /// How far the zone this clock stands in is ahead of UTC.
  final Duration offset;

  @override
  UtcInstant now() => _now;

  @override
  BusinessDate today() => BusinessDate.of(_now.value.add(offset));

  void advance(Duration duration) =>
      _now = UtcInstant(_now.value.add(duration));
}

/// How long from [now] (a local time) until the next local midnight, when
/// "today" turns: what a screen left open waits before it moves on.
Duration untilNextMidnight(DateTime now) {
  final midnight = DateTime(now.year, now.month, now.day + 1);
  return midnight.difference(now);
}
