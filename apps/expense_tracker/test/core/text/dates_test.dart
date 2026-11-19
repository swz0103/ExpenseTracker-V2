import 'package:expense_tracker/src/core/formatting/dates.dart';
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
}
