import 'package:core/foundation_values.dart';

import 'card_billing.dart';

/// A purchase of [total] paid in [count] installments: equal parts rounded
/// down, the whole remainder in the first one, as Taiwan card issuers bill
/// it.
List<int> installmentShares(int total, int count) {
  if (count < 1 || total < 0) {
    throw const CreditCardException(CreditCardError.invalidInput);
  }
  final each = total ~/ count;
  return [total - each * (count - 1), for (var i = 1; i < count; i++) each];
}

/// The scheduled closes [count] installments are billed on: one a month
/// from [first], on [closingDay] or the month's last day.
List<BusinessDate> installmentCloses(
  BusinessDate first,
  int closingDay,
  int count,
) => [
  for (var index = 0; index < count; index++)
    () {
      final (year, month) = shiftMonth(first.year, first.month, index);
      final lastDay = daysInMonth(year, month);
      return BusinessDate(
        year,
        month,
        closingDay <= lastDay ? closingDay : lastDay,
      );
    }(),
];

/// The first scheduled close of installments of a purchase posted on
/// [postedOn], and the closing day they keep after it.
(BusinessDate, int) installmentStart(
  CardSchedule schedule,
  BusinessDate postedOn,
) {
  final first = schedule.cycleFor(postedOn).scheduledClose;
  return (first, schedule.closingDayOn(first));
}

/// The day each of [count] instalments of a purchase posted on [postedOn]
/// is billed: the day the statement it falls in actually closes, moved
/// closes and earlier billing days included. The one schedule the
/// balances and the journal both bill instalments by.
List<BusinessDate> installmentBillingDays(
  CardSchedule schedule,
  BusinessDate postedOn,
  int count,
) {
  final (first, closingDay) = installmentStart(schedule, postedOn);
  return [
    for (final close in installmentCloses(first, closingDay, count))
      schedule.datesOf(close).$1,
  ];
}

/// What refunds of a purchase in instalments do to what its card is
/// billed (refund vs instalments): each refund cancels, on its own day,
/// as much of the instalments not billed by then as it gives back,
/// billed at once so it nets with the refund, and each later instalment
/// shrinks by its share of what was cancelled (shared by the largest
/// remainder over what each had left, so none grows). A purchase
/// refunded in full is settled on the refund's day. [schedule] is the
/// purchase's billing days and shares in order; [refunds] each refund's
/// day and amount, in the order kept, worked through by day. The answer
/// is, for each refund in the order given, the changes it makes to what
/// is billed on each day (more billed positive), which come to nothing.
/// The one rule the balances and the journal both follow.
List<List<(BusinessDate, int)>> refundedInstalments(
  List<(BusinessDate, int)> schedule,
  List<(BusinessDate, int)> refunds,
) {
  final days = [for (final (day, _) in schedule) day];
  final shares = [for (final (_, share) in schedule) share];
  final order = List<int>.generate(refunds.length, (i) => i)
    ..sort((a, b) {
      final byDay = refunds[a].$1.compareTo(refunds[b].$1);
      return byDay != 0 ? byDay : a.compareTo(b);
    });
  final changes = List<List<(BusinessDate, int)>>.filled(
    refunds.length,
    const [],
  );
  for (final i in order) {
    final (day, amount) = refunds[i];
    final later = [
      for (var k = 0; k < days.length; k++)
        if (days[k].compareTo(day) > 0 && shares[k] > 0) k,
    ];
    final unbilled = later.fold(0, (sum, k) => sum + shares[k]);
    final cancelled = amount < unbilled ? amount : unbilled;
    if (cancelled <= 0) continue;
    final kept = Money(
      Currency.units,
      BigInt.from(unbilled - cancelled),
    ).allocate([for (final k in later) BigInt.from(shares[k])]);
    final lines = <(BusinessDate, int)>[(day, cancelled)];
    for (final (j, k) in later.indexed) {
      final left = kept[j].minorUnits.toInt();
      if (left != shares[k]) lines.add((days[k], left - shares[k]));
      shares[k] = left;
    }
    changes[i] = lines;
  }
  return changes;
}
