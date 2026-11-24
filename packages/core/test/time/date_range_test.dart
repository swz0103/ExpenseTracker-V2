import 'package:core/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  test('a range counts both ends', () {
    final range = DateRange(
      BusinessDate(2026, 1, 8),
      BusinessDate(2026, 11, 22),
    );
    // 318 days between, plus the first: 319.
    expect(range.days, 319);
    expect(
      DateRange(BusinessDate(2026, 3, 4), BusinessDate(2026, 3, 4)).days,
      1,
    );
  });

  test('containment, equality and order guard', () {
    final range = DateRange(
      BusinessDate(2026, 3, 1),
      BusinessDate(2026, 3, 31),
    );
    expect(range.contains(BusinessDate(2026, 3, 1)), isTrue);
    expect(range.contains(BusinessDate(2026, 3, 31)), isTrue);
    expect(range.contains(BusinessDate(2026, 4, 1)), isFalse);
    expect(
      range,
      DateRange(BusinessDate(2026, 3, 1), BusinessDate(2026, 3, 31)),
    );
    expect(range.toString(), '2026-03-01..2026-03-31');
    expect(
      () => DateRange(BusinessDate(2026, 3, 2), BusinessDate(2026, 3, 1)),
      throwsArgumentError,
    );
  });
}
