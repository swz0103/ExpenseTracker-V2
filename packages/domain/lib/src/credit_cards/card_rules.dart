/// Where a card's last statement stands on a given day: the one place
/// that decides whether a bill is paid, due, due today or overdue.
library;

import 'package:core/foundation_values.dart' show BusinessDate;

/// The state of a card's last statement.
sealed class CardBillStatus {
  const CardBillStatus();
}

/// No statement has closed yet, so nothing is billed.
final class BillNotYetBilled extends CardBillStatus {
  const BillNotYetBilled();
}

/// Billed and owed, payable by [dueOn], [daysLeft] (one or more) away.
final class BillDue extends CardBillStatus {
  const BillDue(this.dueOn, this.daysLeft);

  final BusinessDate dueOn;
  final int daysLeft;

  @override
  bool operator ==(Object other) =>
      other is BillDue && other.dueOn == dueOn && other.daysLeft == daysLeft;

  @override
  int get hashCode => Object.hash(dueOn, daysLeft);
}

/// Billed and owed, and today is the last day to pay.
final class BillDueToday extends CardBillStatus {
  const BillDueToday(this.dueOn);

  final BusinessDate dueOn;

  @override
  bool operator ==(Object other) =>
      other is BillDueToday && other.dueOn == dueOn;

  @override
  int get hashCode => dueOn.hashCode;
}

/// Still owed [days] (one or more) after [dueOn].
final class BillOverdue extends CardBillStatus {
  const BillOverdue(this.dueOn, this.days);

  final BusinessDate dueOn;
  final int days;

  @override
  bool operator ==(Object other) =>
      other is BillOverdue && other.dueOn == dueOn && other.days == days;

  @override
  int get hashCode => Object.hash(dueOn, days);
}

/// Nothing is left to pay on the statement.
final class BillPaid extends CardBillStatus {
  const BillPaid();
}

/// Where the last statement stands on [today]: [owed] is what is still to
/// pay on it (zero or less when paid), [dueOn] its due day, null when no
/// statement has closed yet. [payBy] is the day it can still be paid
/// without being late, when [dueOn] falls on a day off and the payment
/// moves to the next business day; the days left or late count to it,
/// while the status keeps [dueOn] as the card states it.
CardBillStatus cardBillStatus({
  required int owed,
  required BusinessDate? dueOn,
  required BusinessDate today,
  BusinessDate? payBy,
}) {
  if (dueOn == null) return const BillNotYetBilled();
  if (owed <= 0) return const BillPaid();
  final last = payBy ?? dueOn;
  final left = DateTime.utc(
    last.year,
    last.month,
    last.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  if (left > 0) return BillDue(dueOn, left);
  if (left == 0) return BillDueToday(dueOn);
  return BillOverdue(dueOn, -left);
}
