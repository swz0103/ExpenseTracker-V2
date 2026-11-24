// Round 5: recurring items. Seeded random items (monthly, weekly, daily,
// yearly; paused, ended; some with past bookings) in a book whose "today" is
// 2026-11-24; every invariant is checked for each seed and a failure is cut
// down to a minimal item set.
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/recurring/model/recurring_schedule.dart';
import 'package:expense_tracker/src/features/reminders/ui/reminders_section.dart'
    show reminderBookOf;
import 'package:flutter_test/flutter_test.dart';

import '../../baseline/baseline_ledger.dart';
import '../../support/invariant_book.dart';

final today = day(2026, 11, 24);

String d(DateTime x) => x.toIso8601String().substring(0, 10);

/// Random recurring items and the bookings they already have.
({List<Recurring> items, List<Entry> history}) genItems(int seed, {int n = 4}) {
  final r = Random(seed * 7919);
  final items = <Recurring>[];
  final history = <Entry>[];
  var eid = 0;
  for (var i = 0; i < n; i++) {
    final unit = RepeatUnit.values[r.nextInt(4)];
    final every = switch (unit) {
      RepeatUnit.day => 1 + r.nextInt(9),
      RepeatUnit.week => 1 + r.nextInt(2),
      RepeatUnit.month => 1 + r.nextInt(3),
      RepeatUnit.year => 1 + r.nextInt(2),
    };
    final start = day(2026, 1, 1).add(Duration(days: r.nextInt(300)));
    final end = r.nextInt(100) < 20
        ? start.add(Duration(days: 60 + r.nextInt(250)))
        : null;
    final item = Recurring(
      id: 'r$i',
      name: '項目$i',
      amount: 100 + r.nextInt(900),
      day: start.day,
      account: 'bank',
      category: '飲食',
      unit: unit,
      every: every,
      start: start,
      end: end,
      active: r.nextInt(100) < 85,
      auto: false,
    );
    items.add(item);
    if (r.nextInt(100) < 70) {
      // the app's own bookings: every due date from the start up to a random one
      final dues = <DateTime>[];
      for (
        var m = DateTime.utc(start.year, start.month);
        !m.isAfter(day(2026, 10, 1));
        m = DateTime.utc(m.year, m.month + 1)
      ) {
        dues.addAll(item.dueIn(m.year, m.month));
      }
      if (dues.isEmpty) continue;
      final upTo = r.nextInt(dues.length);
      for (var k = 0; k <= upTo; k++) {
        history.add(
          entryOf(
            'h${eid++}',
            dues[k],
            EntryType.expense,
            item.amount,
            'bank',
            category: '飲食',
          ).withRecurring(item.id),
        );
      }
    }
  }
  return (items: items, history: history);
}

extension on Entry {
  Entry withRecurring(String id) => Entry(
    id: this.id,
    date: date,
    type: type,
    amount: amount,
    account: account,
    category: category,
    recurring: id,
  );
}

Ledger bookOf(List<Recurring> items, List<Entry> history) {
  final l = emptyBook(today: today, recurring: items);
  for (final e in history) {
    l.entryCommands.add(e);
  }
  return l;
}

/// Books every due period the way 入帳 does, one at a time; false if it does
/// not settle in [limit] bookings.
bool bookAll(Ledger l, Recurring item, {int limit = 500}) {
  for (var i = 0; i < limit; i++) {
    final pending = l.recurringService.pendingDate(item);
    if (pending == null || pending.isAfter(l.today)) return true;
    l.recurringCommands.confirm(item);
  }
  return false;
}

String? runProperty(
  String name,
  String? Function(List<Recurring>, List<Entry>) check, {
  List<int>? seedList,
}) {
  final seeds = seedList ?? [for (var i = 1; i <= 60; i++) i];
  final failing = <int>[];
  String? first;
  ({List<Recurring> items, List<Entry> history})? firstGen;
  for (final s in seeds) {
    final g = genItems(s);
    final msg = check(g.items, g.history);
    if (msg != null) {
      failing.add(s);
      if (first == null) {
        first = msg;
        firstGen = g;
      }
    }
  }
  final out = StringBuffer(
    '[$name] seeds tried ${seeds.length}, failing ${failing.length} $failing',
  );
  if (first != null) {
    // shrink: drop items, then history entries
    var items = [...firstGen!.items];
    var history = [...firstGen.history];
    bool bad(List<Recurring> i, List<Entry> h) {
      try {
        return check(i, h) != null;
      } catch (_) {
        return false;
      }
    }

    for (var changed = true; changed;) {
      changed = false;
      for (var k = 0; k < items.length; k++) {
        final i2 = [...items]..removeAt(k);
        final h2 = [
          for (final e in history)
            if (e.recurring != items[k].id) e,
        ];
        if (bad(i2, h2)) {
          items = i2;
          history = h2;
          changed = true;
          break;
        }
      }
      for (var k = 0; k < history.length && !changed; k++) {
        final h2 = [...history]..removeAt(k);
        if (bad(items, h2)) {
          history = h2;
          changed = true;
        }
      }
    }
    out.writeln();
    out.writeln('  first failure (unshrunk): $first');
    out.writeln(
      '  minimal: ${items.length} item(s), ${history.length} existing booking(s); today ${d(today)}',
    );
    for (final r in items) {
      out.writeln(
        '    item ${r.id}: ${r.unit.name} every ${r.every}, start ${d(r.start!)}'
        '${r.end != null ? ', end ${d(r.end!)}' : ''}, ${r.active ? 'active' : 'paused'}',
      );
    }
    out.writeln(
      '    bookings: ${[for (final e in history) '${e.recurring}@${d(e.date)}'].join(', ')}',
    );
    out.write('  on the minimal set: ${check(items, history)}');
  }
  // ignore: avoid_print
  print(out);
  return first == null ? null : out.toString();
}

void expectHolds(String? f) => expect(f, isNull, reason: f ?? '');

void main() {
  test('Q1 after booking every due period nothing is pending, nothing unposted, '
      'and each period has exactly one booking on its day', () {
    expectHolds(
      runProperty('Q1', (items, history) {
        final l = bookOf(items, history);
        for (final item in items) {
          if (!bookAll(l, item)) {
            return '${item.id}: confirm loop does not settle in 500 bookings';
          }
        }
        for (final item in items) {
          if (!item.active) {
            if (l.recurringService.pendingDate(item) != null) {
              return '${item.id} paused but pending';
            }
            continue;
          }
          final p = l.recurringService.pendingDate(item);
          if (p != null && !p.isAfter(today)) {
            return '${item.id}: pending ${d(p)} still due';
          }
          final left = l.recurringService.unpostedDates(
            item,
            from: day(2000, 1, 1),
            to: today,
          );
          if (left.isNotEmpty) {
            return '${item.id}: unposted still lists ${left.map(d)}';
          }
          if (l.recurringService.due.any((r) => r.id == item.id)) {
            return '${item.id} in due list';
          }
          // per month: bookings == due dates not after today
          final mine = [
            for (final e in l.entries.all)
              if (e.recurring == item.id) e,
          ];
          // periods from before the item's first booking, or before this month
          // when it has none, are never asked for (by the service's rule)
          final firstBooked = mine.isEmpty
              ? today
              : (mine.map((e) => e.date).toList()..sort()).first;
          for (
            var m = DateTime.utc(2026, 1);
            !m.isAfter(DateTime.utc(2026, 11));
            m = DateTime.utc(2026, m.month + 1)
          ) {
            final booked = l.recurringService.confirmationsIn(
              item,
              m.year,
              m.month,
            );
            final dues = [
              for (final x in item.dueIn(m.year, m.month))
                if (!x.isAfter(today)) x,
            ];
            if (DateTime.utc(
              m.year,
              m.month,
            ).isBefore(DateTime.utc(firstBooked.year, firstBooked.month))) {
              continue;
            }
            if (booked.length != dues.length) {
              return '${item.id} ${m.year}-${m.month}: ${booked.length} bookings for ${dues.length} due days ${dues.map(d)}';
            }
            final dated = [for (final e in booked) e.date]..sort();
            for (var k = 0; k < dues.length; k++) {
              if (dated[k] != dues[k]) {
                return '${item.id}: booking dated ${d(dated[k])}, period was ${d(dues[k])}';
              }
            }
          }
        }
        return null;
      }),
    );
  });

  test('Q2 bookDue (auto) books the same days as confirming one by one', () {
    expectHolds(
      runProperty('Q2', (items, history) {
        final a = bookOf(items, history);
        for (final item in a.recurring.all) {
          bookAll(a, item);
        }
        final auto = [for (final i in items) i.copyWith(auto: true)];
        final b = bookOf(auto, history);
        // More than one period waiting is listed first (D61): confirmed here.
        var runs = 0;
        while (runs < 20) {
          final due = b.recurringCommands.bookDue();
          var booked = due.booked;
          for (final h in due.held) {
            booked += b.recurringCommands.bookDays(h.item, h.days);
          }
          if (booked == 0) break;
          runs++;
        }
        String key(Ledger l) => ([
          for (final e in l.entries.all)
            if (e.recurring != null) '${e.recurring}@${d(e.date)}',
        ]..sort()).join(' ');
        if (key(a) != key(b)) {
          return 'confirm-loop books ${key(a).length} chars vs bookDue ${key(b).length} (differs)';
        }
        return null;
      }),
    );
  });

  test('Q3 deleting a booking and restoring it gives back the same schedule', () {
    expectHolds(
      runProperty('Q3', (items, history) {
        final l = bookOf(items, history);
        for (final item in items) {
          bookAll(l, item);
        }
        String snap(Ledger l) {
          final b = StringBuffer();
          for (final r in l.recurring.all) {
            b.write(
              '${r.id} skipped=${(r.skipped.map(d).toList()..sort())} '
              'pending=${l.recurringService.pendingDate(r) == null ? '-' : d(l.recurringService.pendingDate(r)!)} '
              'next=${l.recurringService.nextDate(r) == null ? '-' : d(l.recurringService.nextDate(r)!)} '
              'unposted=${l.recurringService.unpostedDates(r, from: day(2020, 1, 1), to: day(2027, 6, 30)).map(d)}; ',
            );
          }
          for (var m = 8; m <= 12; m++) {
            final plan = monthPlan(l.recurring, l.recurringService, 2026, m);
            for (final k in plan.keys.toList()..sort()) {
              for (final x in plan[k]!) {
                b.write(
                  '${x.item.id}@$m/$k:${x.booked != null
                      ? 'B'
                      : x.skipped
                      ? 'S'
                      : '-'} ',
                );
              }
            }
          }
          return b.toString();
        }

        for (final e in [
          for (final e in l.entries.all)
            if (e.recurring != null) e,
        ]) {
          final before = snap(l);
          final removed = l.entryCommands.remove(e.id);
          if (removed == null) return 'could not delete booking ${e.id}';
          final mid = snap(l);
          if (mid == before) {
            return 'deleting booking ${e.recurring}@${d(e.date)} changed nothing (not skipped)';
          }
          if (!l.entryCommands.restore(removed)) return 'restore refused';
          final after = snap(l);
          if (after != before) {
            return 'delete + restore of ${e.recurring}@${d(e.date)} changed the schedule:\n before: $before\n after:  $after';
          }
        }
        return null;
      }),
    );
  });

  test('Q4 skip -> 恢復 -> 入帳 books the day that was restored', () {
    expectHolds(
      runProperty('Q4', (items, history) {
        final l = bookOf(items, history);
        for (final item in items) {
          bookAll(l, item);
        }
        for (final e in [
          for (final e in l.entries.all)
            if (e.recurring != null) e,
        ]) {
          final item = l.recurring.byId(e.recurring!)!;
          // A paused item offers no 入帳 (its days show as paused).
          if (!item.active) continue;
          final dueDay = l.recurringService.dueDayOf(e);
          if (dueDay == null) continue;
          l.entryCommands.remove(e.id); // the day is let go
          l.recurringCommands.unskip(l.recurring.byId(item.id)!, dueDay); // 恢復
          // the calendar now shows dueDay as due (入帳); pressing it opens the
          // composer with recurringService.booking(item)
          final booking = l.recurringService.booking(
            l.recurring.byId(item.id)!,
          );
          if (booking.date != dueDay) {
            return '${item.id}: after delete + 恢復 of ${d(dueDay)}, 入帳 would book on '
                '${d(booking.date)} (pendingDate ${l.recurringService.pendingDate(l.recurring.byId(item.id)!)})';
          }
          return null; // one probe per book is enough; the first decides
        }
        return null;
      }),
    );
  });

  test('Q5 pendingDate == first unposted date of the same month window, and the '
      'reminders list is exactly the unposted dates', () {
    expectHolds(
      runProperty('Q5', (items, history) {
        final l = bookOf(items, history);
        final book = reminderBookOf(l);
        // some books are partly booked: book half of the items
        for (final item in items.take(2)) {
          bookAll(l, item);
        }
        for (final item in l.recurring.all) {
          final p = l.recurringService.pendingDate(item);
          final eom = day(2026, 12, 0);
          final un = l.recurringService.unpostedDates(
            item,
            from: day(2000, 1, 1),
            to: eom,
          );
          final firstUn = un.isEmpty ? null : un.first;
          if (p != firstUn) {
            return '${item.id}: pendingDate ${p == null ? '-' : d(p)} but unposted through this month starts ${firstUn == null ? '-' : d(firstUn)}';
          }
        }
        for (final since in [
          today,
          today.subtract(const Duration(days: 30)),
          today.add(const Duration(days: 20)),
        ]) {
          final listed = <String>{
            for (final r in book.reminders(since: since))
              if (r.recurring != null) '${r.recurring}@${d(r.day)}',
          };
          final want = <String>{};
          final last = today.add(const Duration(days: 62));
          for (final item in l.recurring.all) {
            for (final x in l.recurringService.unpostedDates(
              item,
              from: since,
              to: last,
            )) {
              want.add('${item.id}@${d(x)}');
            }
          }
          if (!(listed.length == want.length && listed.containsAll(want))) {
            return 'reminders(since ${d(since)}) ${listed.toList()..sort()} != unposted ${want.toList()..sort()}';
          }
        }
        return null;
      }),
    );
  });

  test('Q6 from the month of the latest booking on, the calendar (monthPlan) marks '
      'as unbooked exactly the days the service would book', () {
    expectHolds(
      runProperty('Q6', (items, history) {
        final l = bookOf(items, history);
        for (final item in l.recurring.all) {
          for (var m = 3; m <= 12; m++) {
            final plan = monthPlan(l.recurring, l.recurringService, 2026, m);
            final shown = <String>{
              for (final k in plan.keys)
                for (final x in plan[k]!)
                  if (x.item.id == item.id &&
                      !x.settled &&
                      !x.day.isAfter(today))
                    d(x.day),
            };
            final wanted = {
              for (final x in l.recurringService.unpostedDates(
                item,
                from: day(2026, m, 1),
                to: day(2026, m + 1, 0),
              ))
                if (!x.isAfter(today)) d(x),
            };
            final mine = [
              for (final e in l.entries.all)
                if (e.recurring == item.id) e.date,
            ];
            final latest = mine.isEmpty ? today : (mine..sort()).last;
            if (DateTime.utc(
              2026,
              m,
            ).isBefore(DateTime.utc(latest.year, latest.month))) {
              continue;
            }
            if (item.active &&
                !(shown.length == wanted.length && shown.containsAll(wanted))) {
              return '${item.id} $m月: calendar shows $shown as due but the service would book $wanted';
            }
          }
        }
        return null;
      }),
    );
  });
  test('Q6b a past day the calendar offers 入帳 for is the day 入帳 books', () {
    expectHolds(
      runProperty('Q6b', (items, history) {
        final l = bookOf(items, history);
        for (final item in l.recurring.where2()) {
          for (var m = 1; m <= 10; m++) {
            final plan = monthPlan(l.recurring, l.recurringService, 2026, m);
            for (final k in plan.keys.toList()..sort()) {
              for (final x in plan[k]!) {
                if (x.item.id != item.id || x.settled || x.day.isAfter(today)) {
                  continue;
                }
                if (x.statusOn(today) != RecurringPeriodStatus.due) continue;
                // 入帳 on the calendar books the day it is pressed for (D66).
                final booking = l.recurringService.booking(item, day: x.day);
                if (booking.date != x.day) {
                  return '${item.id}: calendar offers 入帳 for ${d(x.day)} (status due) but it would book ${d(booking.date)}';
                }
              }
            }
          }
        }
        return null;
      }),
    );
  });
}

extension on RecurringReader {
  List<Recurring> where2() => [
    for (final r in all)
      if (r.active) r,
  ];
}
