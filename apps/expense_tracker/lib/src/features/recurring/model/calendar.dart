import '../../../core/ledger/ledger.dart';

/// One time a recurring item falls due on the calendar, and the entry
/// that booked it, if one has.
final class Due {
  const Due(this.item, this.day, this.booked);

  final Recurring item;
  final DateTime day;
  final Entry? booked;
}

/// Each day of [year]/[month] with what falls due on it, the dearest
/// first: every active item's dates that month, each matched to that
/// month's bookings in order, as [Ledger.pendingDate] counts them.
Map<int, List<Due>> monthPlan(Ledger ledger, int year, int month) {
  final days = <int, List<Due>>{};
  for (final item in ledger.recurring) {
    if (!item.active) continue;
    final dates = item.datesIn(year, month);
    final booked = ledger.confirmationsIn(item, year, month);
    for (final (i, day) in dates.indexed) {
      (days[day.day] ??= []).add(
        Due(item, day, i < booked.length ? booked[i] : null),
      );
    }
  }
  for (final list in days.values) {
    list.sort(
      (a, b) => ledger
          .recurringWorth(b.item)
          .compareTo(ledger.recurringWorth(a.item)),
    );
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
      if (d >= today.day && plan[d]!.any((x) => x.booked == null)) return d;
    }
    for (final d in days) {
      if (plan[d]!.any((x) => x.booked == null)) return d;
    }
  }
  return days.first;
}

/// The categories a new item is most likely in: the [count] used most by
/// entries of that side, then the others in their order.
List<Category> usualCategories(
  Ledger ledger, {
  required bool income,
  int count = 5,
}) {
  final open = ledger.categoriesFor(income: income);
  final uses = <String, int>{};
  for (final e in ledger.entries) {
    uses[e.category] = (uses[e.category] ?? 0) + 1;
  }
  final sorted = [...open]
    ..sort((a, b) => (uses[b.name] ?? 0).compareTo(uses[a.name] ?? 0));
  return sorted.take(count).toList();
}

/// The next [count] days [item] falls due from [from] on.
List<DateTime> nextTimes(Recurring item, DateTime from, {int count = 3}) {
  final times = <DateTime>[];
  for (var k = 0; k < 60 && times.length < count; k++) {
    final month = DateTime.utc(from.year, from.month + k);
    for (final d in item.datesIn(month.year, month.month)) {
      if (!d.isBefore(DateTime.utc(from.year, from.month, from.day))) {
        times.add(d);
        if (times.length == count) break;
      }
    }
  }
  return times;
}
