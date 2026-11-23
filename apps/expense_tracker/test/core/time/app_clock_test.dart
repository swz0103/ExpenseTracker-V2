import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/time/app_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(AppClock.reset);

  test('the app reads the time a test sets, until it is reset', () {
    final clock = FixedClock(UtcInstant(DateTime.utc(2027, 1, 1, 15, 59)));
    AppClock.use(clock);
    expect(AppClock.now(), DateTime.utc(2027, 1, 1, 15, 59).toLocal());
    clock.advance(const Duration(minutes: 2));
    expect(AppClock.now().toUtc(), DateTime.utc(2027, 1, 1, 16, 1));

    AppClock.reset();
    final phone = DateTime.now();
    expect(AppClock.now().difference(phone).inSeconds.abs(), lessThan(5));
    expect(AppClock.now().isUtc, isFalse);
  });

  test('today is the phone\'s own calendar day, as a UTC midnight', () {
    // 05:00 UTC on 1 October is still 30 September in Los Angeles
    // (UTC-7): the ledger's today follows the phone, not Taipei.
    AppClock.use(
      FixedClock(
        UtcInstant(DateTime.utc(2026, 10, 1, 5)),
        offset: const Duration(hours: -7),
      ),
    );
    expect(AppClock.today(), DateTime.utc(2026, 9, 30));
    // The same instant in Taipei (UTC+8) is 13:00 on 1 October.
    AppClock.use(
      FixedClock(
        UtcInstant(DateTime.utc(2026, 10, 1, 5)),
        offset: const Duration(hours: 8),
      ),
    );
    expect(AppClock.today(), DateTime.utc(2026, 10, 1));
    expect(AppClock.clock, isA<FixedClock>());
  });
}
