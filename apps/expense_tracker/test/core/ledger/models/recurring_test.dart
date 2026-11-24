import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Recurring _item({
  int day = 5,
  RepeatUnit unit = RepeatUnit.month,
  int every = 1,
  DateTime? start,
}) => Recurring(
  id: 'r',
  name: 'r',
  amount: 100,
  day: day,
  account: 'bank',
  category: '居家',
  unit: unit,
  every: every,
  start: start,
);

void main() {
  test('R1: an item from before items had a start falls on its day every '
      'month, with no first day made up', () {
    final old = _item(day: 31);
    expect(old.datesIn(2024, 2), [DateTime.utc(2024, 2, 29)]);
    expect(old.datesIn(1999, 12), [DateTime.utc(1999, 12, 31)]);
  });

  test('F82: a monthly item falls on its day, counted from its start', () {
    final item = _item(day: 10, every: 2, start: DateTime.utc(2026, 11, 1));
    expect(item.datesIn(2026, 11), [DateTime.utc(2026, 11, 10)]);
    expect(item.datesIn(2026, 12), isEmpty);
    expect(item.datesIn(2027, 1), [DateTime.utc(2027, 1, 10)]);
    expect(item.fallsOn(DateTime.utc(2027, 1, 10)), isTrue);
    expect(item.fallsOn(DateTime.utc(2027, 1, 1)), isFalse);
  });

  test('R3: how far apart its dates may lie', () {
    expect(_item(unit: RepeatUnit.day, every: 9).monthsApart, 1);
    expect(_item(unit: RepeatUnit.week, every: 2).monthsApart, 1);
    expect(_item(every: 3).monthsApart, 3);
    // Every 3 years: 3 × 12 months.
    expect(_item(unit: RepeatUnit.year, every: 3).monthsApart, 36);
  });

  test('R3: the next dates are found however far apart', () {
    final rare = _item(
      unit: RepeatUnit.year,
      every: 3,
      start: DateTime.utc(2026, 3, 3),
    );
    expect(rare.datesFrom(DateTime.utc(2026, 3, 4), count: 2), [
      DateTime.utc(2029, 3, 3),
      DateTime.utc(2032, 3, 3),
    ]);
    // The day itself counts.
    expect(rare.datesFrom(DateTime.utc(2026, 3, 3)), [
      DateTime.utc(2026, 3, 3),
    ]);
    final weekly = _item(
      unit: RepeatUnit.week,
      start: DateTime.utc(2026, 10, 2),
    );
    expect(weekly.datesFrom(DateTime.utc(2026, 10, 30), count: 3), [
      DateTime.utc(2026, 10, 30),
      DateTime.utc(2026, 11, 6),
      DateTime.utc(2026, 11, 13),
    ]);
  });
}
