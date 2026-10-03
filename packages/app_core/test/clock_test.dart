import 'package:app_core/app_core.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  test('today is the date in Taiwan, whatever the device zone', () {
    final clock = FixedClock(UtcInstant(DateTime.utc(2026, 9, 30, 16, 30)));
    // 00:30 on 1 October in Taipei: a new month already.
    expect(clock.today(), BusinessDate(2026, 10, 1));
    clock.advance(const Duration(hours: 7));
    expect(clock.today(), BusinessDate(2026, 10, 1));
    final before = FixedClock(UtcInstant(DateTime.utc(2026, 9, 30, 15, 59)));
    expect(before.today(), BusinessDate(2026, 9, 30));
  });
}
