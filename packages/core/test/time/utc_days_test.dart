import 'package:core/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  test('dayOf keeps a value\'s own day at UTC midnight', () {
    expect(dayOf(DateTime(2026, 3, 4, 23, 59)), DateTime.utc(2026, 3, 4));
    expect(dayOf(DateTime.utc(2026, 3, 4, 0, 0, 1)), DateTime.utc(2026, 3, 4));
    expect(dayOf(DateTime.utc(2026, 3, 4)), DateTime.utc(2026, 3, 4));
  });

  test('monthStart moves by months across years both ways', () {
    final day = DateTime.utc(2026, 11, 24);
    expect(monthStart(day), DateTime.utc(2026, 11));
    // November + 2 months = January of the next year.
    expect(monthStart(day, 2), DateTime.utc(2027, 1));
    // November - 11 months = December of the year before.
    expect(monthStart(day, -11), DateTime.utc(2025, 12));
  });

  test('monthEnd is the last day, leap Februaries and months past 12 '
      'included', () {
    expect(monthEnd(2026, 2), DateTime.utc(2026, 2, 28));
    expect(monthEnd(2028, 2), DateTime.utc(2028, 2, 29));
    expect(monthEnd(2026, 4), DateTime.utc(2026, 4, 30));
    // Month 13 of 2026 is January 2027; month 0 is December 2025.
    expect(monthEnd(2026, 13), DateTime.utc(2027, 1, 31));
    expect(monthEnd(2026, 0), DateTime.utc(2025, 12, 31));
  });

  test('monthStarts counts each month from the first to the last that '
      'starts by the end', () {
    expect(monthStarts(DateTime.utc(2026, 11, 20), DateTime.utc(2027, 2, 1)), [
      DateTime.utc(2026, 11),
      DateTime.utc(2026, 12),
      DateTime.utc(2027, 1),
      DateTime.utc(2027, 2),
    ]);
    // 31 January ends before 1 February starts.
    expect(monthStarts(DateTime.utc(2026, 12, 5), DateTime.utc(2027, 1, 31)), [
      DateTime.utc(2026, 12),
      DateTime.utc(2027, 1),
    ]);
    expect(
      monthStarts(DateTime.utc(2026, 5, 2), DateTime.utc(2026, 4, 30)),
      isEmpty,
    );
  });

  test('yearBefore keeps the day, 29 February becoming the 28th', () {
    expect(yearBefore(DateTime.utc(2026, 3, 31)), DateTime.utc(2025, 3, 31));
    expect(yearBefore(DateTime.utc(2028, 2, 29)), DateTime.utc(2027, 2, 28));
    expect(yearBefore(DateTime.utc(2027, 1, 1)), DateTime.utc(2026, 1, 1));
  });
}
