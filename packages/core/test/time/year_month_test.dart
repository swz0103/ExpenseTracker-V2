import 'package:core/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  test('months move across years', () {
    expect(YearMonth(2026, 12).next, YearMonth(2027, 1));
    expect(YearMonth(2026, 1).previous, YearMonth(2025, 12));
    // 2026-10 - 11 months = 2025-11.
    expect(YearMonth(2026, 10).addMonths(-11), YearMonth(2025, 11));
    // 2026-10 + 27 months: 2 months to 2026-12, 1 to 2027-01, 24 more = 2029-01.
    expect(YearMonth(2026, 10).addMonths(27), YearMonth(2029, 1));
    expect(YearMonth(2025, 11).monthsUntil(YearMonth(2026, 10)), 11);
  });

  test('first and last days, with leap Februaries', () {
    expect(YearMonth(2024, 2).lastDay, BusinessDate(2024, 2, 29));
    expect(YearMonth(2026, 2).lastDay, BusinessDate(2026, 2, 28));
    expect(YearMonth(2026, 4).days, 30);
    expect(YearMonth(2026, 4).firstDay, BusinessDate(2026, 4, 1));
    expect(YearMonth(2026, 2).dayClamped(31), BusinessDate(2026, 2, 28));
    expect(YearMonth(2026, 2).dayClamped(5), BusinessDate(2026, 2, 5));
  });

  test('order, containment, text and parsing guards', () {
    final months = [YearMonth(2027, 1), YearMonth(2026, 12), YearMonth(2026, 2)]
      ..sort();
    expect(months, [
      YearMonth(2026, 2),
      YearMonth(2026, 12),
      YearMonth(2027, 1),
    ]);
    expect(YearMonth(2026, 2).contains(BusinessDate(2026, 2, 28)), isTrue);
    expect(YearMonth(2026, 2).contains(BusinessDate(2026, 3, 1)), isFalse);
    expect(YearMonth(2026, 2).toString(), '2026-02');
    expect(YearMonth.of(DateTime.utc(2026, 7, 9)), YearMonth(2026, 7));
    expect(YearMonth(2026, 7).asUtcMidnight, DateTime.utc(2026, 7));
    expect(() => YearMonth(2026, 13), throwsFormatException);
    expect(() => YearMonth(2026, 0), throwsFormatException);
  });
}
