import 'package:core/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  BusinessDate d(int y, int m, int day) => BusinessDate(y, m, day);

  group('the official table', () {
    test('covers 2025 to 2027 and nothing else', () {
      expect(taiwanHolidays.years, {2025, 2026, 2027});
    });
    test('names the days off and the make-up workdays', () {
      expect(taiwanHolidays.holidays[d(2026, 10, 9)], '補假');
      expect(taiwanHolidays.holidays[d(2027, 2, 5)], '農曆除夕');
      expect(taiwanHolidays.workdays[d(2025, 2, 8)], '補行上班');
      // 2025: 15 weekday holidays; 2026: 16; 2027: 17.
      expect(taiwanHolidays.holidays.length, 15 + 16 + 17);
      expect(taiwanHolidays.workdays.length, 1);
    });
  });

  group('isBusinessDay', () {
    test('a weekday holiday is not one, a make-up Saturday is', () {
      expect(
        taiwanHolidays.isBusinessDay(d(2026, 10, 9)),
        isA<Verified<bool>>(),
      );
      expect(taiwanHolidays.isBusinessDay(d(2026, 10, 9)).value, isFalse);
      expect(taiwanHolidays.isBusinessDay(d(2026, 10, 8)).value, isTrue);
      // 2025-02-08 is a Saturday worked for the Lunar New Year.
      expect(taiwanHolidays.isBusinessDay(d(2025, 2, 8)).value, isTrue);
      // 2026-10-10 is a Saturday (National Day on a weekend).
      expect(taiwanHolidays.isBusinessDay(d(2026, 10, 10)).value, isFalse);
    });
    test('a year not in the table answers from weekends only', () {
      final answer = taiwanHolidays.isBusinessDay(d(2028, 1, 3));
      expect(answer, isA<WeekendsOnly<bool>>());
      expect((answer as WeekendsOnly<bool>).year, 2028);
      // 2028-01-03 is a Monday.
      expect(answer.value, isTrue);
    });
  });

  group('next and previous business day', () {
    test('skip the Lunar New Year and the weekend around it', () {
      // 2026-02-13 Fri; 14-15 weekend; 16-20 holidays; 21-22 weekend.
      expect(
        taiwanHolidays.nextBusinessDay(d(2026, 2, 13)).value,
        d(2026, 2, 23),
      );
      expect(
        taiwanHolidays.previousBusinessDay(d(2026, 2, 23)).value,
        d(2026, 2, 13),
      );
    });
    test('onOrAfter keeps a business day and moves a day off', () {
      expect(taiwanHolidays.onOrAfter(d(2026, 10, 8)).value, d(2026, 10, 8));
      // Fri 2026-10-09 off, weekend 10-11: Monday 10-12.
      expect(taiwanHolidays.onOrAfter(d(2026, 10, 9)).value, d(2026, 10, 12));
    });
    test('crossing into an unknown year says so', () {
      // Fri 2027-12-31 is off; 2028-01-01/02 weekend; Mon 2028-01-03.
      final answer = taiwanHolidays.nextBusinessDay(d(2027, 12, 30));
      expect(answer, isA<WeekendsOnly<BusinessDate>>());
      expect(answer.value, d(2028, 1, 3));
    });
  });

  group('addBusinessDays', () {
    test('T+2 over a holiday Friday', () {
      // Wed 2026-10-07: Thu 10-08 is day 1, Fri 10-09 off, weekend,
      // Mon 10-12 is day 2.
      final answer = taiwanHolidays.addBusinessDays(d(2026, 10, 7), 2);
      expect(answer, isA<Verified<BusinessDate>>());
      expect(answer.value, d(2026, 10, 12));
      expect(
        taiwanHolidays.addBusinessDays(d(2026, 10, 7), 0).value,
        d(2026, 10, 7),
      );
      expect(
        () => taiwanHolidays.addBusinessDays(d(2026, 10, 7), -1),
        throwsArgumentError,
      );
    });
  });

  group('closedAlso', () {
    final office = HolidayCalendar(
      years: {2026, 2027},
      holidays: {d(2026, 10, 9): '補假'},
      workdays: {d(2026, 10, 17): '補行上班', d(2026, 10, 24): '補行上班'},
    );
    final market = office.closedAlso(
      HolidayCalendar(
        years: {2025, 2026},
        holidays: {d(2026, 10, 13): '休市', d(2026, 10, 24): '休市'},
        workdays: const {},
      ),
    );
    test('closes the days of both', () {
      // Fri 10-09 is off in the first, Tue 10-13 in the second.
      expect(market.isBusinessDay(d(2026, 10, 9)).value, isFalse);
      expect(market.isBusinessDay(d(2026, 10, 13)).value, isFalse);
      expect(market.isBusinessDay(d(2026, 10, 14)).value, isTrue);
      // Thu 10-08 + 2: Fri off, weekend, Mon 10-12 is day 1, Tue off,
      // Wed 10-14 is day 2.
      expect(market.addBusinessDays(d(2026, 10, 8), 2).value, d(2026, 10, 14));
    });
    test('a make-up Saturday is worked unless the other closes it', () {
      expect(market.isBusinessDay(d(2026, 10, 17)).value, isTrue);
      expect(market.isBusinessDay(d(2026, 10, 24)).value, isFalse);
      expect(market.workdays.keys, [d(2026, 10, 17)]);
    });
    test('knows only the years both cover', () {
      expect(market.years, {2026});
      expect(market.isBusinessDay(d(2026, 6, 1)), isA<Verified<bool>>());
      expect(market.isBusinessDay(d(2027, 6, 1)), isA<WeekendsOnly<bool>>());
      expect(market.isBusinessDay(d(2025, 6, 2)), isA<WeekendsOnly<bool>>());
    });
  });

  test('a table with an unknown kind of day is refused', () {
    expect(
      () => HolidayCalendar.parse('years:2026\n2026-01-02,festival,x'),
      throwsFormatException,
    );
  });
}
