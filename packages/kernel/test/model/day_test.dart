import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

void main() {
  test('a day is year, month and day as one number, and back', () {
    final d = Day.of(BusinessDate(2026, 2, 7));
    expect(d.ymd, 20260207);
    expect((d.year, d.month, d.day), (2026, 2, 7));
    expect(d.date, BusinessDate(2026, 2, 7));
    expect(d.monthKey, 202602);
    expect(Day.stored(20260207), d);
  });

  test('the first and last day of its month, the day before', () {
    expect(Day.stored(20240215).lastOfMonth.ymd, 20240229); // leap year
    expect(Day.stored(20250215).lastOfMonth.ymd, 20250228);
    expect(Day.stored(20261231).lastOfMonth.ymd, 20261231);
    expect(Day.stored(20261231).firstOfMonth.ymd, 20261201);
    expect(Day.stored(20260301).previous.ymd, 20260228);
    expect(Day.stored(20260101).previous.ymd, 20251231);
  });

  test('days compare as numbers; before every record comes first', () {
    final a = Day.stored(20260101);
    final b = Day.stored(20260102);
    expect(a < b && a <= b && b > a && b >= a && a <= a && a >= a, isTrue);
    expect(Day.beforeAll < Day.of(BusinessDate(1, 1, 2)), isTrue);
    expect(Day.beforeAll.date, BusinessDate(1, 1, 1));
  });

  test('positions order by day, then by the order kept', () {
    final a = (date: Day.stored(20260101), seq: 9);
    final b = (date: Day.stored(20260102), seq: 1);
    final c = (date: Day.stored(20260102), seq: 2);
    expect(comparePositions(a, b), lessThan(0));
    expect(comparePositions(c, b), greaterThan(0));
    expect(comparePositions(b, b), 0);
  });
}
