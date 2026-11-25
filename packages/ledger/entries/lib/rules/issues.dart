/// Why the ledger will not keep a record, or what it says before keeping
/// one, as the rules of this package find it. The words for the person
/// are the app's to choose, in one place: an issue here is a value, never
/// a sentence.
library;

/// How much an issue weighs: an [error] refuses the record; a [warning]
/// is said before it is kept and lets it be kept.
enum Severity { error, warning }

/// One thing the rules found wrong with a record.
sealed class RecordIssue {
  const RecordIssue();

  /// Whether the record is refused for it.
  Severity get severity => Severity.error;

  bool get isError => severity == Severity.error;

  @override
  String toString() => '$runtimeType';
}

// ---- entries -------------------------------------------------------------

/// No amount, or for a trade no shares and price.
final class MissingAmount extends RecordIssue {
  const MissingAmount({required this.trade});

  /// Whether the entry is a purchase or sale of shares.
  final bool trade;
}

/// An amount larger than the app keeps: [max] in the smallest unit of the
/// account's currency.
final class AmountTooLarge extends RecordIssue {
  const AmountTooLarge(this.max);

  final int max;
}

/// More shares than the app keeps in one entry: [max].
final class SharesTooLarge extends RecordIssue {
  const SharesTooLarge(this.max);

  final int max;
}

/// A fee or tax below nothing.
final class NegativeCharge extends RecordIssue {
  const NegativeCharge();
}

/// A day that is not a UTC midnight, which the ledger's day and month
/// lookups take every date to be.
final class DateNotMidnight extends RecordIssue {
  const DateNotMidnight();
}

/// An entry paid from or into an account the book does not have.
final class UnknownAccount extends RecordIssue {
  const UnknownAccount();
}

/// A transfer with no receiving account, or one the book does not have.
final class MissingDestination extends RecordIssue {
  const MissingDestination();
}

/// A transfer out of and into the same account.
final class SameAccountTransfer extends RecordIssue {
  const SameAccountTransfer();
}

/// Spending or income in another currency, with no rate yet and no
/// amount in NT$ given.
final class MissingHomeAmount extends RecordIssue {
  const MissingHomeAmount();
}

/// Money sent out of a card, which only spends.
final class CardTransferOut extends RecordIssue {
  const CardTransferOut();
}

/// A fee on a transfer out of a foreign account.
final class ForeignTransferFee extends RecordIssue {
  const ForeignTransferFee();
}

/// A fee on a card payment.
final class CardPaymentFee extends RecordIssue {
  const CardPaymentFee();
}

/// A transfer between currencies with no amount received given.
final class MissingReceivedAmount extends RecordIssue {
  const MissingReceivedAmount();
}

/// A card paid straight from a foreign account.
final class ForeignCardPayment extends RecordIssue {
  const ForeignCardPayment();
}

/// A trade or dividend in a foreign account.
final class ForeignInvestment extends RecordIssue {
  const ForeignInvestment();
}

/// Shares paid for from a card or a loan.
final class InvestmentFromDebt extends RecordIssue {
  const InvestmentFromDebt();
}

/// A reduction of more shares than are held.
final class ReductionExceedsHolding extends RecordIssue {
  const ReductionExceedsHolding(this.held);

  /// The shares held before it.
  final int held;
}

/// Supplementary premium larger than the dividend it is taken from.
final class TaxExceedsDividend extends RecordIssue {
  const TaxExceedsDividend();
}

/// A trade or dividend with no stock chosen.
final class MissingHolding extends RecordIssue {
  const MissingHolding();
}

/// A trade of no shares.
final class MissingShares extends RecordIssue {
  const MissingShares();
}

/// An entry dated further ahead than [days] after today (D25).
final class DateTooFarAhead extends RecordIssue {
  const DateTooFarAhead(this.days);

  /// How far ahead an entry may be dated.
  final int days;
}

/// A trade or dividend dated after today: shares change hands on the day
/// they do, so only spending, income and transfers may be 預定 (D25).
final class InvestmentPlanned extends RecordIssue {
  const InvestmentPlanned();
}

/// A day trade (當日沖銷) that is not a sale: only a sale closes a
/// position opened the same day (D6).
final class DayTradeNotSale extends RecordIssue {
  const DayTradeNotSale();
}

/// A sale of more shares than are held by then. With [later], it is not
/// the record written that is short but a sale or reduction after it,
/// such as when a purchase it sold from is taken away: the one type every
/// path that refuses an oversold sale gives (D12).
final class SaleExceedsHolding extends RecordIssue {
  const SaleExceedsHolding({this.later = false});

  /// A later sale or reduction, not the record itself, would be short.
  final bool later;
}

/// A refund of card spending paid into another account.
final class RefundToOtherAccount extends RecordIssue {
  const RefundToOtherAccount();
}

/// An entry changed in a form that was opened on it, after it was
/// deleted meanwhile: kept, it would stand both in the book and in the
/// trash (D78).
final class EntryDeleted extends RecordIssue {
  const EntryDeleted();
}

/// A refund of more than is left to refund.
final class RefundExceedsRemaining extends RecordIssue {
  const RefundExceedsRemaining(this.left);

  /// What is left to refund.
  final int left;
}

/// A part of a split of nothing, or less.
final class SplitPartNotPositive extends RecordIssue {
  const SplitPartNotPositive();
}

/// Parts of a split that do not add up to the amount: [difference] is
/// the amount less their sum.
final class SplitTotalMismatch extends RecordIssue {
  const SplitTotalMismatch(this.difference);

  final int difference;
}

/// Instalments on anything but card spending.
final class InstallmentsOffCard extends RecordIssue {
  const InstallmentsOffCard();
}

/// A count of instalments below none or above [max].
final class InstallmentsOutOfRange extends RecordIssue {
  const InstallmentsOutOfRange(this.max);

  final int max;
}

/// Shares bought leaving the paying account below nothing: [after] is
/// its balance once they are paid for. Said before saving; the entry may
/// still be kept.
final class NegativeBalanceAfter extends RecordIssue {
  const NegativeBalanceAfter(this.after);

  final int after;

  @override
  Severity get severity => Severity.warning;
}

// ---- recurring items -----------------------------------------------------

/// A recurring item repeating every fewer than one day, week, month or
/// year: its dates would never move on.
final class IntervalTooSmall extends RecordIssue {
  const IntervalTooSmall();
}

/// A day of the month outside 1 to 31.
final class DayOutOfRange extends RecordIssue {
  const DayOutOfRange();
}

/// A recurring item that ends before it starts.
final class EndsBeforeStart extends RecordIssue {
  const EndsBeforeStart();
}

// ---- accounts ------------------------------------------------------------

/// An account with no name.
final class BlankName extends RecordIssue {
  const BlankName();
}

/// A card's statement closing day outside 1 to 31.
final class ClosingDayOutOfRange extends RecordIssue {
  const ClosingDayOutOfRange();
}

/// A card's payment day outside 1 to 31.
final class DueDayOutOfRange extends RecordIssue {
  const DueDayOutOfRange();
}

/// A credit limit below nothing.
final class NegativeCreditLimit extends RecordIssue {
  const NegativeCreditLimit();
}

/// A loan's yearly rate below nothing (D116).
final class NegativeLoanRate extends RecordIssue {
  const NegativeLoanRate();
}

/// A loan's yearly rate above [max] hundredths of a percent, taken for a
/// typo (D118).
final class LoanRateTooHigh extends RecordIssue {
  const LoanRateTooHigh(this.max);

  final int max;
}

/// A statement close moved where the card's schedule cannot hold it:
/// more than a week from its scheduled day, or not before its payment.
final class CloseMoveRefused extends RecordIssue {
  const CloseMoveRefused();
}

// ---- budgets -------------------------------------------------------------

/// A budget limit below nothing.
final class NegativeBudgetLimit extends RecordIssue {
  const NegativeBudgetLimit();
}

/// A warning share outside 1% to 100%.
final class WarningOutOfRange extends RecordIssue {
  const WarningOutOfRange();
}
