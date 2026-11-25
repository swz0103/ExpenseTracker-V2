import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  test('today is the calendar day in the clock\'s own zone', () {
    // 16:30 UTC on 30 September: still 30 September in UTC ...
    final utc = FixedClock(UtcInstant(DateTime.utc(2026, 9, 30, 16, 30)));
    expect(utc.today(), BusinessDate(2026, 9, 30));
    // ... already 1 October in Taipei (UTC+8) ...
    final taipei = FixedClock(
      UtcInstant(DateTime.utc(2026, 9, 30, 16, 30)),
      offset: const Duration(hours: 8),
    );
    expect(taipei.today(), BusinessDate(2026, 10, 1));
    // ... and still 30 September in Los Angeles (UTC-7 in summer time).
    final losAngeles = FixedClock(
      UtcInstant(DateTime.utc(2026, 10, 1, 5)),
      offset: const Duration(hours: -7),
    );
    expect(losAngeles.today(), BusinessDate(2026, 9, 30));
  });

  test('a fixed clock moves only when told', () {
    final clock = FixedClock(UtcInstant(DateTime.utc(2026, 9, 30, 23, 30)));
    expect(clock.today(), BusinessDate(2026, 9, 30));
    clock.advance(const Duration(hours: 1));
    expect(clock.now(), UtcInstant(DateTime.utc(2026, 10, 1, 0, 30)));
    expect(clock.today(), BusinessDate(2026, 10, 1));
  });

  test('the system clock gives the phone\'s own day', () {
    final local = DateTime.now();
    final today = const SystemClock().today();
    // Unless midnight passed between the two reads.
    expect(
      today.day == local.day ||
          today.day == local.add(const Duration(minutes: 1)).day,
      isTrue,
    );
  });

  test('time until the next local midnight', () {
    // 23:59:30 → 30 seconds left.
    expect(
      untilNextMidnight(DateTime(2026, 10, 1, 23, 59, 30)),
      const Duration(seconds: 30),
    );
    // 00:00 → a whole day (24 h, no daylight saving in Taiwan).
    expect(untilNextMidnight(DateTime(2026, 10, 1)).inHours, 24);
  });
}
