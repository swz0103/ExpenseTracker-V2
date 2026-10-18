import 'dart:math';

import 'records.dart';

/// A card's billing cycle: when its statements close, moved closes
/// included, and how much of a purchase each statement has billed. A
/// statement closes at the end of its day.
extension CardCycle on Account {
  /// The last statement closing on or before [day].
  DateTime closingOn(DateTime day) {
    DateTime closing(int year, int month) {
      final scheduled = scheduledClose(year, month);
      return closes[scheduled] ?? scheduled;
    }

    // A close moved by up to a week may fall in the month before or
    // after its own: the latest of the three not after [day].
    DateTime? latest;
    for (final back in const [1, 0, -1]) {
      final close = closing(day.year, day.month - back);
      if (!close.isAfter(day) && (latest == null || close.isAfter(latest))) {
        latest = close;
      }
    }
    return latest ?? closing(day.year, day.month - 2);
  }

  /// The close the billing day sets in [year]/[month], before any move.
  DateTime scheduledClose(int year, int month) => DateTime.utc(
    year,
    month,
    min(closingDay ?? 1, DateTime.utc(year, month + 1, 0).day),
  );

  /// How much of [e], charged on this card, has reached its statements by
  /// [at]: all of it, or the instalments billed so far.
  int billed(Entry e, DateTime at) {
    final count = e.installments;
    if (count < 2) return e.amount;
    final periods = billedPeriods(e, at);
    if (periods == 0) return 0;
    // Equal parts rounded down, the remainder in the first one, as card
    // issuers bill it and as the ledger's own schedule has it.
    final each = e.amount ~/ count;
    return periods >= count ? e.amount : e.amount - each * (count - periods);
  }

  /// How many instalments of [e] have been billed by [at].
  int billedPeriods(Entry e, DateTime at) {
    var periods = 0;
    var month = DateTime.utc(e.date.year, e.date.month);
    while (!month.isAfter(at) && periods < e.installments) {
      final closing = closingOn(_lastDayOf(month));
      if (!closing.isBefore(e.date) && !closing.isAfter(at)) periods++;
      month = DateTime.utc(month.year, month.month + 1);
    }
    return periods;
  }

  static DateTime _lastDayOf(DateTime month) =>
      DateTime.utc(month.year, month.month + 1, 0);
}
