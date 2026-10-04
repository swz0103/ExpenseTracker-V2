import 'dart:math';

import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

/// Billing-cycle properties over every closing and due day and many seeded
/// random dates (code audit P3).
void main() {
  final twd = Currency.of('TWD');

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
      final terms = CreditCardTerms(
        workspace: WorkspaceId(PublicId.generate()),
        cardId: PublicId.generate(),
        currency: twd,
        closingDay: closing,
        dueDay: due,
      );
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
}
