import 'package:core/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  test('UTC instant retains microseconds and converts an explicit offset', () {
    final instant = UtcInstant(
      DateTime.parse('2026-09-26T01:02:03.123456+08:00'),
    );
    expect(instant.toString(), '2026-09-25T17:02:03.123456Z');
    expect(UtcInstant.parse(instant.toString()), instant);
    expect(instant.value.isUtc, isTrue);
  });
  test('strict instant parsing rejects normalized or ambiguous input', () {
    for (final value in [
      '2026-09-26',
      '2026-09-26T00:00:00',
      '2026-09-26T00:00:00+08:00',
      '2026-02-30T00:00:00Z',
      '2026-09-26T24:00:00Z',
      '2026-09-26T00:60:00Z',
      '2026-09-26T00:00:60Z',
      '2026-09-26T00:00:00.1234567Z',
    ]) {
      expect(() => UtcInstant.parse(value), throwsFormatException);
    }
  });
}
