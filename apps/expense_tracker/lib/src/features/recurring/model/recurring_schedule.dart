import '../../../core/ledger/ledger.dart';

/// One time a recurring item falls due on the calendar, and the entry
/// that booked it, if one has.
final class Due {
  const Due(this.item, this.day, this.booked, {this.skipped = false});

  final Recurring item;
  final DateTime day;
  final Entry? booked;

  /// Let go: its booking was deleted, so it is not booked again.
  final bool skipped;

  /// Booked or let go: nothing more to do for it.
  bool get settled => booked != null || skipped;

  /// Where this period stands on [today], as the recurring rules decide.
  RecurringPeriodStatus statusOn(DateTime today) => recurringPeriodStatus(
    active: item.active,
    booked: booked != null,
    skipped: skipped,
    day: day,
    today: today,
  );
}

/// Each day of [year]/[month] with what falls due on it, the dearest
/// first: every active item's dates that month, each with the booking
/// that settles it, as `RecurringService.settled` matches them.
Map<int, List<Due>> monthPlan(
  RecurringReader recurring,
  RecurringService service,
  int year,
  int month,
) {
  final days = <int, List<Due>>{};
  for (final item in recurring.all) {
    if (!item.active) continue;
    final booked = service.bookedDays(item);
    for (final day in item.datesIn(year, month)) {
      final skipped = item.skipped.contains(day);
      (days[day.day] ??= []).add(
        Due(item, day, skipped ? null : booked[day], skipped: skipped),
      );
    }
  }
  for (final list in days.values) {
    list.sort((a, b) => service.worth(b.item).compareTo(service.worth(a.item)));
  }
  return days;
}

/// The day to show first: the first day from today on with something
/// still to book, else the first day due and not booked, else the first
/// day with anything; null for a month with nothing.
int? firstShown(Map<int, List<Due>> plan, DateTime today, int year, int month) {
  final days = plan.keys.toList()..sort();
  if (days.isEmpty) return null;
  final current = year == today.year && month == today.month;
  if (current) {
    for (final d in days) {
      if (d >= today.day && plan[d]!.any((x) => !x.settled)) return d;
    }
    for (final d in days) {
      if (plan[d]!.any((x) => !x.settled)) return d;
    }
  }
  return days.first;
}

/// The next [count] days [item] falls due from [from] on, however far
/// apart (R3).
List<DateTime> nextTimes(Recurring item, DateTime from, {int count = 3}) =>
    item.datesFrom(from, count: count);
