import 'entry_rules.dart' show maxAmountAnyCurrency;
import 'issues.dart';

/// Why a recurring item of these fields cannot be kept: an amount of
/// nothing, an interval that would never move its dates on, a day no
/// month has, an end before its start. [amount] is in the smallest unit
/// of its account's currency.
List<RecordIssue> recurringIssues({
  required int amount,
  required int every,
  required int day,
  DateTime? start,
  DateTime? end,
}) => [
  if (amount <= 0) const MissingAmount(trade: false),
  if (amount > maxAmountAnyCurrency) AmountTooLarge(maxAmountAnyCurrency),
  ...recurringShapeIssues(every: every, day: day),
  if (start != null && end != null && end.isBefore(start))
    const EndsBeforeStart(),
];

/// What a recurring item read back from elsewhere, such as a backup, must
/// be for its dates to be worked out at all: an interval of at least one
/// and a day of the month, and an amount from nothing to the most kept. An amount of
/// nothing, which only stops it being booked, and an end before its
/// start, which only ends it, still read.
List<RecordIssue> recurringShapeIssues({
  int amount = 0,
  required int every,
  required int day,
}) => [
  if (amount < 0) const MissingAmount(trade: false),
  if (amount > maxAmountAnyCurrency) AmountTooLarge(maxAmountAnyCurrency),
  if (every < 1) const IntervalTooSmall(),
  if (day < 1 || day > 31) const DayOutOfRange(),
];

/// Why an account of these fields cannot be kept: no name, a card's days
/// outside the month, a credit limit or a loan's [loanRate] below
/// nothing. A form that does not ask for the name passes none.
List<RecordIssue> accountIssues({
  String? name,
  int? closingDay,
  int? dueDay,
  int? limit,
  int? loanRate,
}) => [
  if (name != null && name.trim().isEmpty) const BlankName(),
  ...accountShapeIssues(
    closingDay: closingDay,
    dueDay: dueDay,
    limit: limit,
    loanRate: loanRate,
  ),
];

/// [accountIssues] less the name: what an account read back from
/// elsewhere must be. Its [opening] balance, when given, may be below
/// nothing (a debt), but no further from it than the most kept. A loan's
/// [loanRate] (hundredths of a percent a year) is never below nothing
/// (D116).
List<RecordIssue> accountShapeIssues({
  int? closingDay,
  int? dueDay,
  int? limit,
  int? opening,
  int? loanRate,
}) => [
  if (closingDay != null && (closingDay < 1 || closingDay > 31))
    const ClosingDayOutOfRange(),
  if (dueDay != null && (dueDay < 1 || dueDay > 31)) const DueDayOutOfRange(),
  if (limit != null && limit < 0) const NegativeCreditLimit(),
  if (loanRate != null && loanRate < 0) const NegativeLoanRate(),
  if ((limit != null && limit > maxAmountAnyCurrency) ||
      (opening != null && opening.abs() > maxAmountAnyCurrency))
    AmountTooLarge(maxAmountAnyCurrency),
];

/// Why a budget of [limit] warning at [warning] percent cannot be kept.
List<RecordIssue> budgetIssues({required int limit, required int warning}) => [
  if (limit < 0) const NegativeBudgetLimit(),
  if (limit > maxAmountAnyCurrency) AmountTooLarge(maxAmountAnyCurrency),
  if (warning < 1 || warning > 100) const WarningOutOfRange(),
];
