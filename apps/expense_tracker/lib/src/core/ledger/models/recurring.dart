import 'dart:math';

/// How often a recurring item comes round.
enum RepeatUnit { day, week, month, year }

final class Recurring {
  const Recurring({
    required this.id,
    required this.name,
    required this.amount,
    required this.day,
    required this.account,
    required this.category,
    this.active = true,
    this.unit = RepeatUnit.month,
    this.every = 1,
    this.start,
    this.end,
    this.income = false,
    this.merchant = '',
    this.auto = false,
    this.skipped = const {},
    this.openFrom,
  });

  final String id;
  final String name;
  final int amount;

  /// Days it fell due that were let go: its entry deleted, so that day
  /// is not booked again. Restoring the entry, or 恢復 on the calendar,
  /// takes the day out again.
  final Set<DateTime> skipped;

  /// The earliest day brought back by 恢復, from which its days are asked
  /// for again even when no booking is left from before (D66); null when
  /// none was.
  final DateTime? openFrom;

  /// Booked by itself on its day, when the ledger is next opened, rather
  /// than confirmed each time.
  final bool auto;

  /// Day of the month a monthly item falls due; a 31st falls on the last
  /// day of a shorter month.
  final int day;
  final String account;
  final String category;
  final bool active;
  final RepeatUnit unit;

  /// Every how many [unit]s.
  final int every;

  /// From when it falls due: a weekly item keeps its weekday, a yearly
  /// one its date, and a monthly one counts its months from it. Every
  /// item written since items had a start has one (the day it was made,
  /// unless chosen); one written before has none and falls due on [day]
  /// of every month, as it did then, with no first day.
  final DateTime? start;

  /// The last day it may fall due, if it ends.
  final DateTime? end;

  /// Money coming in, such as a salary, rather than going out.
  final bool income;
  final String merchant;

  Recurring copyWith({
    String? name,
    int? amount,
    String? account,
    String? category,
    bool? active,
    bool? auto,
    Set<DateTime>? skipped,
    String? merchant,
    DateTime? openFrom,
  }) => Recurring(
    id: id,
    name: name ?? this.name,
    amount: amount ?? this.amount,
    day: day,
    account: account ?? this.account,
    category: category ?? this.category,
    active: active ?? this.active,
    unit: unit,
    every: every,
    start: start,
    end: end,
    income: income,
    merchant: merchant ?? this.merchant,
    auto: auto ?? this.auto,
    skipped: skipped ?? this.skipped,
    openFrom: openFrom ?? this.openFrom,
  );

  /// The days of [year]/[month] it falls due and was not let go.
  List<DateTime> dueIn(int year, int month) => [
    for (final d in datesIn(year, month))
      if (!skipped.contains(d)) d,
  ];

  /// Whether [d] is one of the days it falls due, let go or not.
  bool fallsOn(DateTime d) => datesIn(d.year, d.month).contains(d);

  /// The days in [year]/[month] it falls due; none for an item whose
  /// interval would never move its dates on (every below 1), which the
  /// ledger refuses to write but an older book may hold.
  List<DateTime> datesIn(int year, int month) {
    if (every < 1) return const [];
    final last = DateTime.utc(year, month + 1, 0);
    final first = start;
    final stop = end;
    bool keep(DateTime d) =>
        (first == null || !d.isBefore(first)) &&
        (stop == null || !d.isAfter(stop));
    // An item from before items had a start: on [day], every month.
    if (first == null) {
      final d = DateTime.utc(year, month, min(day, last.day));
      return keep(d) ? [d] : const [];
    }
    final dates = <DateTime>[];
    switch (unit) {
      case RepeatUnit.day || RepeatUnit.week:
        final step = every * (unit == RepeatUnit.week ? 7 : 1);
        final monthStart = DateTime.utc(year, month);
        final gap = monthStart.difference(first).inDays;
        var d = gap <= 0
            ? first
            : first.add(Duration(days: (gap + step - 1) ~/ step * step));
        while (!d.isAfter(last)) {
          if (keep(d)) dates.add(d);
          d = d.add(Duration(days: step));
        }
      case RepeatUnit.month:
        // On [day], which the form keeps when only the start moves (F82).
        final months = (year - first.year) * 12 + month - first.month;
        if (months >= 0 && months % every == 0) {
          final d = DateTime.utc(year, month, min(day, last.day));
          if (keep(d)) dates.add(d);
        }
      case RepeatUnit.year:
        final years = year - first.year;
        if (month == first.month && years >= 0 && years % every == 0) {
          final d = DateTime.utc(year, month, min(first.day, last.day));
          if (keep(d)) dates.add(d);
        }
    }
    return dates;
  }

  /// How many months apart its dates may lie: what a look ahead for its
  /// next date must cover (R3: a yearly item every three years is found).
  int get monthsApart => switch (unit) {
    RepeatUnit.day || RepeatUnit.week => 1,
    RepeatUnit.month => max(every, 1),
    RepeatUnit.year => 12 * max(every, 1),
  };

  /// The first [count] days from [from] on (counted) it falls due, let go
  /// or not, earliest first: looked for as far ahead as [count] periods
  /// reach, so a rare item is found as surely as a monthly one.
  List<DateTime> datesFrom(DateTime from, {int count = 1}) {
    final found = <DateTime>[];
    final day = DateTime.utc(from.year, from.month, from.day);
    // A period further, for a date at the end of a month.
    final months = monthsApart * (count + 1);
    for (var k = 0; k <= months && found.length < count; k++) {
      final month = DateTime.utc(from.year, from.month + k);
      for (final d in datesIn(month.year, month.month)) {
        if (d.isBefore(day)) continue;
        found.add(d);
        if (found.length == count) break;
      }
    }
    return found;
  }
}
