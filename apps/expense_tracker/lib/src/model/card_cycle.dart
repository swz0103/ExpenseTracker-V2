import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart';

import 'records.dart';

/// A card's billing cycle, by the ledger's own schedule: when its
/// statements close, moved closes and earlier billing days included, and
/// how much of a purchase each statement has billed. A statement closes at
/// the end of its day.
extension CardBilling on Account {
  /// The billing days, their history and the moved closes, as the ledger
  /// keeps them.
  CardSchedule get schedule => _schedules[this] ??= _scheduleOf(this);

  /// The last statement closing on or before [day].
  DateTime closingOn(DateTime day) => _utc(schedule.lastCloseOn(_day(day)));

  /// The statement whose last day is [end]: its first day and when it
  /// must be paid.
  (DateTime, DateTime) cycleEnding(DateTime end) {
    final cycle = schedule.cycleFor(_day(end));
    return (
      _utc(cycle.startsAfter).add(const Duration(days: 1)),
      _utc(cycle.dueOn),
    );
  }

  /// How much of [e], charged on this card, has reached its statements by
  /// [at]: all of it, or the instalments billed so far.
  int billed(Entry e, DateTime at) {
    final count = e.installments;
    if (count < 2) return e.amount;
    final periods = billedPeriods(e, at);
    return installmentShares(e.amount, count).take(periods).fold(0, _sum);
  }

  /// How many instalments of [e] have been billed by [at]: those whose
  /// statement has closed, on the ledger's own instalment schedule.
  int billedPeriods(Entry e, DateTime at) {
    if (e.installments < 1) return 0;
    final (first, closingDay) = installmentStart(schedule, _day(e.date));
    final until = _day(at);
    var periods = 0;
    for (final close in installmentCloses(first, closingDay, e.installments)) {
      if (schedule.datesOf(close).$1.compareTo(until) > 0) break;
      periods++;
    }
    return periods;
  }
}

int _sum(int a, int b) => a + b;

final _schedules = Expando<CardSchedule>('card schedule');

/// The card's schedule; moved closes the schedule cannot hold are left out.
CardSchedule _scheduleOf(Account a) {
  CardSchedule plain;
  try {
    plain = CardSchedule(
      closingDay: a.closingDay ?? 1,
      dueDay: a.dueDay ?? 15,
      history: a.history,
    );
  } on CreditCardException {
    // Billing days changed twice before one close: the latest stand.
    plain = CardSchedule(closingDay: a.closingDay ?? 1, dueDay: a.dueDay ?? 15);
  }
  final overrides = <CardCycleOverride>[];
  for (final MapEntry(key: scheduled, value: closesOn) in a.closes.entries) {
    try {
      final close = _day(scheduled);
      final override = CardCycleOverride(
        scheduledClose: close,
        closesOn: _day(closesOn),
        dueOn: plain.datesOf(close).$2,
      );
      CardSchedule(
        closingDay: plain.closingDay,
        dueDay: plain.dueDay,
        history: plain.history,
        overrides: [override],
      );
      overrides.add(override);
    } on CreditCardException {
      continue;
    }
  }
  return overrides.isEmpty
      ? plain
      : CardSchedule(
          closingDay: plain.closingDay,
          dueDay: plain.dueDay,
          history: plain.history,
          overrides: overrides,
        );
}

BusinessDate _day(DateTime d) => BusinessDate(d.year, d.month, d.day);

DateTime _utc(BusinessDate d) => DateTime.utc(d.year, d.month, d.day);
