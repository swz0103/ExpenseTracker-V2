import 'dart:math';

import 'package:core/foundation_values.dart';
import 'package:domain/credit_cards.dart';
import 'package:test/test.dart';

/// Billing-cycle properties over every closing and due day and many seeded
/// random dates (code audit P3).
void main() {
  int epochDay(BusinessDate date) {
    final instant = DateTime.utc(date.year, date.month, date.day);
    return instant.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  }

  BusinessDate plus(BusinessDate date, int days) {
    final next = DateTime.utc(date.year, date.month, date.day + days);
    return BusinessDate(next.year, next.month, next.day);
  }

  test('every day falls in exactly one cycle, and cycles chain', () {
    final random = Random(20261007);
    for (var closing = 1; closing <= 31; closing++) {
      final due = 1 + random.nextInt(31);
      final terms = CardSchedule(closingDay: closing, dueDay: due);
      for (var round = 0; round < 60; round++) {
        final date = plus(BusinessDate(2026, 1, 1), random.nextInt(1500));
        final reason = 'closing $closing, due $due, on $date';
        final cycle = terms.cycleFor(date);
        expect(cycle.startsAfter.compareTo(date) < 0, isTrue, reason: reason);
        expect(cycle.closesOn.compareTo(date) >= 0, isTrue, reason: reason);
        expect(cycle.dueOn.compareTo(cycle.closesOn) > 0, isTrue);
        // A cycle lasts about a month and is due within about a month.
        final length = epochDay(cycle.closesOn) - epochDay(cycle.startsAfter);
        expect(length, inInclusiveRange(28, 31), reason: reason);
        // The next day after a close starts the next cycle.
        final next = terms.cycleFor(plus(cycle.closesOn, 1));
        expect(next.startsAfter, cycle.closesOn, reason: reason);
        expect(terms.cycleFor(cycle.closesOn).closesOn, cycle.closesOn);
      }
    }
  });

  test('r13: 3,000 schedules refunded at random: the changes come to '
      'nothing, and no month is billed below zero', () {
    final r = Random(3);
    for (var n = 0; n < 3000; n++) {
      final count = 2 + r.nextInt(11);
      final total = 100 + r.nextInt(50000);
      final shares = installmentShares(total, count).toList();
      final schedule = [
        for (var i = 0; i < count; i++)
          (BusinessDate(2026, 1 + i, 10), shares[i]),
      ];
      final refunds = [
        for (var i = 0, k = 1 + r.nextInt(4); i < k; i++)
          (
            BusinessDate(2026, 1 + r.nextInt(count), 1 + r.nextInt(28)),
            1 + r.nextInt(total),
          ),
      ];
      final changes = refundedInstalments(schedule, refunds);
      final billed = {for (final (d, s) in schedule) d: s};
      var sum = 0;
      for (final list in changes) {
        for (final (d, c) in list) {
          sum += c;
          billed[d] = (billed[d] ?? 0) + c;
        }
      }
      expect(sum, 0, reason: 'n=$n');
      for (final v in billed.values) {
        expect(v, greaterThanOrEqualTo(0), reason: 'n=$n');
      }
    }
  });
}
