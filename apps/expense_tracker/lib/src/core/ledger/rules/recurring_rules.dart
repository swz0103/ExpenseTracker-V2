/// Where one period of a recurring item stands: the one place that
/// decides booked, skipped, due, still to come or paused.
///
/// Lives here until recurring items have a package of their own
/// (`packages/ledger/recurring/rules/`).
library;

import 'package:core/time/utc_days.dart';

/// The state of one date a recurring item falls on.
enum RecurringPeriodStatus {
  /// Its day has not come yet.
  upcoming,

  /// Its day has come and it is not booked.
  due,

  /// Its entry is in the book.
  booked,

  /// Let go: its entry was deleted, so it is not booked again.
  skipped,

  /// The item is paused, so nothing is booked for it.
  paused,
}

/// Where the period of an item falling on [day] stands on [today]:
/// [active] is false for a paused item, [booked] whether its entry is in
/// the book, [skipped] whether it was let go. Days compare as calendar
/// days.
RecurringPeriodStatus recurringPeriodStatus({
  required bool active,
  required bool booked,
  required bool skipped,
  required DateTime day,
  required DateTime today,
}) {
  if (!active) return RecurringPeriodStatus.paused;
  if (booked) return RecurringPeriodStatus.booked;
  if (skipped) return RecurringPeriodStatus.skipped;
  final on = dayOf(day);
  final now = dayOf(today);
  return on.isAfter(now)
      ? RecurringPeriodStatus.upcoming
      : RecurringPeriodStatus.due;
}
