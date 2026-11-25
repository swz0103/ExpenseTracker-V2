import 'package:expense_tracker/src/core/ledger/rules/recurring_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('recurringPeriodStatus', () {
    final today = DateTime.utc(2026, 11, 20);
    RecurringPeriodStatus of(
      DateTime day, {
      bool active = true,
      bool booked = false,
      bool skipped = false,
    }) => recurringPeriodStatus(
      active: active,
      booked: booked,
      skipped: skipped,
      day: day,
      today: today,
    );

    test('a day still to come is upcoming', () {
      expect(of(DateTime.utc(2026, 11, 21)), RecurringPeriodStatus.upcoming);
    });

    test('today and earlier unbooked days are due', () {
      expect(of(today), RecurringPeriodStatus.due);
      expect(of(DateTime.utc(2026, 11, 19)), RecurringPeriodStatus.due);
    });

    test('a booked day is booked, a let-go day is skipped', () {
      expect(of(today, booked: true), RecurringPeriodStatus.booked);
      expect(of(today, skipped: true), RecurringPeriodStatus.skipped);
    });

    test('a paused item is paused whatever its day', () {
      expect(
        of(DateTime.utc(2026, 11, 1), active: false),
        RecurringPeriodStatus.paused,
      );
    });
  });
}
