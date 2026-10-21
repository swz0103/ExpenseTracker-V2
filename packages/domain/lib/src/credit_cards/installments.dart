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
      final month = DateTime.utc(first.year, first.month + index, 1);
      final lastDay = DateTime.utc(month.year, month.month + 1, 0).day;
      return BusinessDate(
        month.year,
        month.month,
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
