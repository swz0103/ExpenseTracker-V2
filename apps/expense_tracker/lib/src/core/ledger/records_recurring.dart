part of 'records.dart';

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
  });

  final String id;
  final String name;
  final int amount;

  /// Days it fell due that were let go: its entry deleted, so that day
  /// is not booked again. Restoring the entry, or 恢復 on the calendar,
  /// takes the day out again.
  final Set<DateTime> skipped;

  /// Booked by itself on its day, when the ledger is next opened, rather
  /// than confirmed each time.
  final bool auto;

  /// Day of the month it falls due, for monthly items without [start].
  final int day;
  final String account;
  final String category;
  final bool active;
  final RepeatUnit unit;

  /// Every how many [unit]s.
  final int every;

  /// The first time it falls due; the weekday, day or date it keeps.
  final DateTime? start;

  /// The last day it may fall due, if it ends.
  final DateTime? end;

  /// Money coming in, such as a salary, rather than going out.
  final bool income;
  final String merchant;

  /// 「每月 5 日」「每 2 週 週五」「每年 3/15」.
  String get rhythm {
    final first = start;
    final n = every == 1 ? '' : ' $every ';
    final weekday = first == null ? '' : ' 週${_weekdays[first.weekday - 1]}';
    final date = first == null ? '' : ' ${first.month}/${first.day}';
    return switch (unit) {
      RepeatUnit.day => '每$n天',
      RepeatUnit.week => '每$n週$weekday',
      RepeatUnit.month =>
        '每$n${every == 1 ? '月' : '個月'} ${first?.day ?? day} 日',
      RepeatUnit.year => '每$n年$date',
    };
  }

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  Recurring copyWith({
    String? name,
    int? amount,
    String? account,
    String? category,
    bool? active,
    bool? auto,
    Set<DateTime>? skipped,
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
    merchant: merchant,
    auto: auto ?? this.auto,
    skipped: skipped ?? this.skipped,
  );

  /// The days in [year]/[month] it falls due.
  /// The days of [year]/[month] it falls due and was not let go.
  List<DateTime> dueIn(int year, int month) => [
    for (final d in datesIn(year, month))
      if (!skipped.contains(d)) d,
  ];

  List<DateTime> datesIn(int year, int month) {
    final last = DateTime.utc(year, month + 1, 0);
    final first = start ?? DateTime.utc(2025, 1, day);
    final stop = end;
    bool keep(DateTime d) =>
        !d.isBefore(first) && (stop == null || !d.isAfter(stop));
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
        final months = (year - first.year) * 12 + month - first.month;
        if (months >= 0 && months % every == 0) {
          final d = DateTime.utc(year, month, min(first.day, last.day));
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
}

/// An entry deleted on [on], kept for a while to be restored.
final class Trashed {
  const Trashed(this.entry, this.on);

  final Entry entry;
  final DateTime on;
}
