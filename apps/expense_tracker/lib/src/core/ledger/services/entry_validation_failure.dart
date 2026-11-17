/// Why the ledger will not keep an entry, as [EntryValidator.validate]
/// finds it. The words for the person are the screens' to choose, in one
/// place (core/messages/validation_messages.dart): a reason here is a value,
/// never a sentence.
///
/// @docImport 'entry_validator.dart';
library;

sealed class EntryValidationFailure {
  const EntryValidationFailure();
}

/// No amount, or for a trade no shares and price.
final class MissingAmount extends EntryValidationFailure {
  const MissingAmount({required this.trade});

  /// Whether the entry is a purchase or sale of shares.
  final bool trade;
}

/// A transfer out of and into the same account.
final class SameAccountTransfer extends EntryValidationFailure {
  const SameAccountTransfer();
}

/// Spending or income in another currency, with no rate yet and no
/// amount in NT$ given.
final class MissingHomeAmount extends EntryValidationFailure {
  const MissingHomeAmount();
}

/// Money sent out of a card, which only spends.
final class CardTransferOut extends EntryValidationFailure {
  const CardTransferOut();
}

/// A fee on a transfer out of a foreign account.
final class ForeignTransferFee extends EntryValidationFailure {
  const ForeignTransferFee();
}

/// A fee on a card payment.
final class CardPaymentFee extends EntryValidationFailure {
  const CardPaymentFee();
}

/// A transfer between currencies with no amount received given.
final class MissingReceivedAmount extends EntryValidationFailure {
  const MissingReceivedAmount();
}

/// A card paid straight from a foreign account.
final class ForeignCardPayment extends EntryValidationFailure {
  const ForeignCardPayment();
}

/// A trade or dividend in a foreign account.
final class ForeignInvestment extends EntryValidationFailure {
  const ForeignInvestment();
}

/// Shares paid for from a card or a loan.
final class InvestmentFromDebt extends EntryValidationFailure {
  const InvestmentFromDebt();
}

/// A reduction of more shares than are held.
final class ReductionExceedsHolding extends EntryValidationFailure {
  const ReductionExceedsHolding(this.held);

  /// The shares held before it.
  final int held;
}

/// Supplementary premium larger than the dividend it is taken from.
final class TaxExceedsDividend extends EntryValidationFailure {
  const TaxExceedsDividend();
}

/// A trade or dividend with no stock chosen.
final class MissingHolding extends EntryValidationFailure {
  const MissingHolding();
}

/// A trade of no shares.
final class MissingShares extends EntryValidationFailure {
  const MissingShares();
}

/// A sale of more shares than are held by then.
final class SaleExceedsHolding extends EntryValidationFailure {
  const SaleExceedsHolding();
}

/// A refund of card spending paid into another account.
final class RefundToOtherAccount extends EntryValidationFailure {
  const RefundToOtherAccount();
}

/// A refund of more than is left to refund.
final class RefundExceedsRemaining extends EntryValidationFailure {
  const RefundExceedsRemaining(this.left);

  /// What is left to refund.
  final int left;
}
