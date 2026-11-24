import 'package:core/foundation_values.dart';
import 'package:domain/data_exchange.dart';
import 'package:test/test.dart';

/// D93: four digits are a Gregorian year, three a Republic of China one,
/// one or two refused with why; nothing before 1950.
void main() {
  BusinessDate? read(String text) => switch (readImportDay(text)) {
    DayRead(:final date) => date,
    DayRefused() => null,
  };
  DayProblem? problem(String text) => switch (readImportDay(text)) {
    DayRead() => null,
    DayRefused(:final problem) => problem,
  };

  test('a four-digit year is Gregorian, in every form', () {
    for (final text in ['2026-03-05', '2026/3/5', '2026.3.5', '20260305']) {
      expect(read(text), BusinessDate(2026, 3, 5), reason: text);
    }
    expect(read(' 2026-03-05 '), BusinessDate(2026, 3, 5));
  });

  test('a three-digit year is the Republic of China\'s', () {
    // 115 + 1911 = 2026.
    expect(read('115/3/5'), BusinessDate(2026, 3, 5));
    expect(read('1150305'), BusinessDate(2026, 3, 5));
    // 39 + 1911 = 1950, the earliest taken.
    expect(read('039/1/1'), BusinessDate(1950, 1, 1));
  });

  test('a year of one or two digits is refused, never guessed (F4)', () {
    // 26/10/01 was read as 26 + 1911 = 1937.
    expect(problem('26/10/01'), DayProblem.shortYear);
    expect(problem('6/1/1'), DayProblem.shortYear);
    expect(problem('261001'), DayProblem.shortYear);
  });

  test('a day before 1950 is refused (F4)', () {
    // The e-invoice M line 0261003: 26 + 1911 = 1937.
    expect(problem('0261003'), DayProblem.tooEarly);
    expect(problem('1949-12-31'), DayProblem.tooEarly);
    expect(read('1950-01-01'), BusinessDate(1950, 1, 1));
    expect(earliestImportYear, 1950);
  });

  test('what is not a day of the calendar is unreadable', () {
    for (final text in [
      '2026-02-30',
      '2026-13-01',
      '2026-00-10',
      '20261340',
      'abc',
      '',
      '2026-03',
      '12345-01-01',
      '2026-1-1-1',
    ]) {
      expect(problem(text), DayProblem.unreadable, reason: text);
    }
    expect(read('2028-02-29'), BusinessDate(2028, 2, 29));
  });
}
