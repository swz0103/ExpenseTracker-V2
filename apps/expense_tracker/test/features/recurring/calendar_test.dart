import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/recurring/model/calendar.dart';
import 'package:flutter_test/flutter_test.dart';

/// 定期交易's calendar: each day with what falls due, matched to its
/// bookings, and the day shown first.
void main() {
  test('a month lays every active item on its days, booked or not', () {
    final ledger = demoLedger();
    final today = ledger.today;
    final plan = monthPlan(ledger, today.year, today.month);
    final shown = [
      for (final list in plan.values)
        for (final d in list) d.item.id,
    ];
    for (final r in ledger.recurring) {
      final times = r.active ? r.datesIn(today.year, today.month).length : 0;
      expect(shown.where((id) => id == r.id).length, times, reason: r.name);
    }
    for (final list in plan.values) {
      for (final d in list) {
        final booked = ledger.confirmationsIn(d.item, today.year, today.month);
        if (d.booked != null) expect(booked, contains(d.booked));
      }
    }
  });

  test('it opens on the next day with something to book', () {
    final ledger = demoLedger();
    final today = ledger.today;
    final plan = monthPlan(ledger, today.year, today.month);
    final day = firstShown(plan, today, today.year, today.month);
    expect(day, isNotNull);
    expect(plan[day]!.any((d) => d.booked == null), isTrue);
  });

  test('the next three times follow the item\'s rhythm', () {
    final ledger = demoLedger();
    final monthly = ledger.recurring.firstWhere((r) => r.every == 1);
    final next = nextTimes(monthly, ledger.today);
    expect(next, hasLength(3));
    expect(next[1].isAfter(next[0]) && next[2].isAfter(next[1]), isTrue);
  });
}
