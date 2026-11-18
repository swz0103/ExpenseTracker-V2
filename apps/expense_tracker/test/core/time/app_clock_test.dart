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
}
