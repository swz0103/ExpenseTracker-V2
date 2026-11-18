import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart';

import 'models/models.dart';

/// What each period bills of [total] paid in [count] instalments, in
/// order: equal parts rounded down, the whole remainder in the first, as
/// Taiwan's card issuers bill it; all of it at once below two.
List<int> installmentAmounts(int total, int count) =>
    count < 2 ? [total] : installmentShares(total, count);

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

  /// Each instalment of [e], charged on this card: the day its statement
  /// closes, from when it counts, and its share. What has been billed by
  /// a day is the sum of the shares up to it, as [billed] works it out.
  ///
  /// Kept with the entry for as long as this card stays as it is: an entry
  /// and a card never change, a card with new billing days is a new one.
  List<(DateTime, int)> billingSteps(Entry e) {
    final kept = _steps[e];
    if (kept != null && identical(kept.$1, this)) return kept.$2;
    final steps = _stepsOf(e);
    _steps[e] = (this, steps);
    return steps;
  }

  List<(DateTime, int)> _stepsOf(Entry e) {
    final count = e.installments;
    if (count < 2) return [(e.date, e.amount)];
    final shares = installmentShares(e.amount, count).toList();
    final (first, closingDay) = installmentStart(schedule, _day(e.date));
    return [
      for (final (k, close) in installmentCloses(
        first,
        closingDay,
        count,
      ).indexed)
        (_utc(schedule.datesOf(close).$1), shares[k]),
    ];
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

/// Each entry's billing steps, with the card they were worked out on.
final _steps = Expando<(Account, List<(DateTime, int)>)>('billing steps');

/// The card's schedule; moved closes the schedule cannot hold are left out.
CardSchedule _scheduleOf(Account a) {
  // A history the schedule cannot hold loses its latest changes first,
  // so statements before them keep their dates.
  late CardSchedule plain;
  for (var keep = a.history.length; keep >= 0; keep--) {
    try {
      plain = CardSchedule(
        closingDay: a.closingDay ?? 1,
        dueDay: a.dueDay ?? 15,
        history: a.history.sublist(0, keep),
      );
      break;
    } on CreditCardException {
      if (keep == 0) rethrow;
    }
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
      // A change the card's schedule refuses is left out.
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
