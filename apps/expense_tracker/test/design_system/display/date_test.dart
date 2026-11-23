import 'package:core/foundation_values.dart'
    show BusinessDate, Verified, WeekendsOnly;
import 'package:expense_tracker/design_system/display/date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sunday = DateTime.utc(2026, 10, 4);

  test('each skeleton writes the date as the app always has', () {
    expect(formatE(sunday), '週日');
    expect(formatMd(sunday), '10/4');
    expect(formatMEd(sunday), '10/4 週日');
    expect(formatYMd(sunday), '2026/10/4');
    expect(formatYM(sunday), '2026/10');
    expect(formatMMMd(sunday), '10 月 4 日');
    expect(formatYMMM(sunday), '2026 年 10 月');
    expect(formatMMMEd(sunday), '10 月 4 日 · 週日');
  });

  test('every weekday has its name, Monday first', () {
    final monday = DateTime.utc(2026, 9, 28);
    expect(
      [for (var i = 0; i < 7; i++) formatE(monday.add(Duration(days: i)))],
      ['週一', '週二', '週三', '週四', '週五', '週六', '週日'],
    );
  });

  test('items are grouped by their day, in the order first met', () {
    final times = [
      DateTime.utc(2026, 10, 4, 9),
      DateTime.utc(2026, 10, 3, 23),
      DateTime.utc(2026, 10, 4, 18),
      DateTime.utc(2026, 9, 30),
    ];
    final days = groupByDay(times.indexed, (t) => t.$2);
    expect(days.keys, [
      DateTime.utc(2026, 10, 4),
      DateTime.utc(2026, 10, 3),
      DateTime.utc(2026, 9, 30),
    ]);
    expect([for (final (i, _) in days[DateTime.utc(2026, 10, 4)]!) i], [0, 2]);
    expect(groupByDay(<DateTime>[], (d) => d), isEmpty);
  });

  test('the week starts on Sunday, everywhere in the app', () {
    expect(weekdayNames, ['日', '一', '二', '三', '四', '五', '六']);
    final sunday = DateTime.utc(2026, 10, 4);
    for (var i = 0; i < 7; i++) {
      final day = sunday.add(Duration(days: i));
      expect(weekdayIndex(day), i);
      expect(weekdayAt(i), day.weekday);
      expect(startOfWeek(day), sunday);
      expect(formatE(day), '週${weekdayNames[i]}');
    }
    // A Saturday belongs to the week begun the Sunday before.
    expect(startOfWeek(DateTime.utc(2026, 10, 3)), DateTime.utc(2026, 9, 27));
  });

  final today = DateTime.utc(2026, 11, 22);

  test('a day carries its year only outside the current one', () {
    expect(formatDay(DateTime.utc(2026, 1, 8), today: today), '1/8');
    expect(formatDay(DateTime.utc(2025, 1, 8), today: today), '2025/1/8');
  });

  test('a range carries years when it is not all in this year (F86)', () {
    expect(
      formatDayRange(
        DateTime.utc(2026, 1, 8),
        DateTime.utc(2026, 11, 22),
        today: today,
      ),
      '1/8 – 11/22',
    );
    // The F86 case: 1780 days cannot fit in one year.
    expect(
      formatDayRange(
        DateTime.utc(2021, 12, 9),
        DateTime.utc(2026, 11, 22),
        today: today,
      ),
      '2021/12/9 – 2026/11/22',
    );
    expect(
      formatDayRange(
        DateTime.utc(2025, 3, 1),
        DateTime.utc(2025, 3, 9),
        today: today,
      ),
      '2025/3/1 – 2025/3/9',
    );
  });

  test('本月 only for the current month (F75)', () {
    expect(monthWord(2026, 11, today: today), '本月');
    expect(monthWord(2026, 9, today: today), '9 月');
    expect(monthWord(2025, 11, today: today), '2025 年 11 月');
  });

  test('relative days and clock times', () {
    expect(relativeDay(DateTime.utc(2026, 11, 22, 21), today: today), '今天');
    expect(relativeDay(DateTime.utc(2026, 11, 21), today: today), '昨天');
    expect(relativeDay(DateTime.utc(2026, 11, 2), today: today), '11/2');
    expect(relativeDay(DateTime.utc(2025, 12, 31), today: today), '2025/12/31');
    expect(formatHm(9, 5), '09:05');
    expect(formatHmSpaced(9, 5), '09 : 05');
    expect(formatTimeField(7), '07');
    expect(formatWhen(DateTime(2026, 11, 21, 8, 14), today: today), '昨天 08:14');
    expect(formatYMdHm(DateTime(2026, 3, 4, 21, 3)), '2026/3/4 21:03');
  });

  test('a due day that moves says where to (PKG-07)', () {
    final due = DateTime.utc(2026, 10, 10);
    // Sat 10-10 → Mon 10-12 on the official calendar.
    expect(postponedTo(due, Verified(BusinessDate(2026, 10, 12))), '順延至 10/12');
    expect(postponedTo(due, Verified(BusinessDate(2026, 10, 10))), isNull);
    expect(
      postponedTo(
        DateTime.utc(2028, 1, 1),
        WeekendsOnly(BusinessDate(2028, 1, 3), 2028),
      ),
      '順延至 1/3（未含國定假日）',
    );
  });

  test('a market change is 今日 only on its own trading day (F25)', () {
    expect(tradingDayWord(DateTime.utc(2026, 11, 22), today: today), '今日');
    // Sunday 11/22: the close is Friday 11/20's.
    expect(tradingDayWord(DateTime.utc(2026, 11, 20), today: today), '11/20');
    expect(
      tradingDayWord(DateTime.utc(2025, 12, 31), today: today),
      '2025/12/31',
    );
  });
}
