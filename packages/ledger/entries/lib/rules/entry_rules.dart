import 'package:core/foundation_values.dart' show Currency;

import '../model/account_kind.dart';
import '../model/entry.dart';
import 'issues.dart';

/// The largest amount kept, in whole units of the account's currency: the
/// most the amount keys can type.
const maxWholeAmount = 999999999;

/// The most monthly instalments a card purchase may be paid in.
const maxInstallments = 60;

/// [maxWholeAmount] in the smallest unit of [currency]: cents for US$.
int maxAmountOf(String currency) {
  var max = maxWholeAmount;
  for (var i = 0; i < Currency.scaleOf(currency); i++) {
    max *= 10;
  }
  return max;
}

/// What the rules need to know of the book around an entry, gathered by
/// whoever asks: the accounts it names, the shares and refund it touches,
/// and the paying account's balance once it is kept.
final class EntryFacts {
  const EntryFacts({
    required this.account,
    this.to,
    this.heldBefore,
    this.oversells = false,
    this.refunded,
    this.balanceAfter,
  });

  /// The account the entry is paid from or into; null when the book has
  /// none of that id.
  final AccountFacts? account;

  /// A transfer's receiving account; null when it names none, or one the
  /// book does not have.
  final AccountFacts? to;

  /// For a reduction, the shares of its stock held before it; null when
  /// the shares are checked otherwise, as by replaying the trades.
  final int? heldBefore;

  /// Whether, with the entry kept, a sale or reduction would take more
  /// shares than are held by then.
  final bool oversells;

  /// The spending a refund gives back, when the book has it.
  final RefundFacts? refunded;

  /// The paying account's balance once the entry is kept, today; null
  /// when not worked out.
  final int? balanceAfter;
}

/// What a refund needs of the spending it gives back.
final class RefundFacts {
  const RefundFacts({
    required this.account,
    required this.kind,
    required this.left,
    this.own = 0,
  });

  /// The account the spending was paid from, and its kind.
  final String account;
  final AccountKind kind;

  /// What is left of it to refund, besides this refund.
  final int left;

  /// What the refund being changed already gave back, which counts as
  /// left for its new amount.
  final int own;
}

/// Everything the ledger has to say about keeping [e]: errors, which
/// refuse it, first in the order a form asks for its fields, then
/// warnings.
List<RecordIssue> entryIssues(Entry e, EntryFacts facts) {
  final found = <RecordIssue>[];
  final from = facts.account;
  final currency = from?.currency ?? homeCode;
  final trade = e.type == EntryType.buy || e.type == EntryType.sell;
  final stock = e.type == EntryType.dividend && e.shares != 0;
  final transfer = e.type == EntryType.transfer;
  final cash = e.type == EntryType.expense || e.type == EntryType.income;
  final to = transfer ? facts.to : null;

  if (!_isMidnight(e.date)) found.add(const DateNotMidnight());
  if (e.amount <= 0 && !stock) found.add(MissingAmount(trade: trade));
  if (e.amount > maxAmountOf(currency)) {
    found.add(AmountTooLarge(maxAmountOf(currency)));
  }
  if (e.fee < 0 || e.tax < 0) found.add(const NegativeCharge());
  if (from == null) found.add(const UnknownAccount());
  if (transfer && e.account == e.to) {
    found.add(const SameAccountTransfer());
  } else if (transfer && to == null) {
    found.add(const MissingDestination());
  }
  if (cash && currency != homeCode && e.home == null) {
    found.add(const MissingHomeAmount());
  }
  if (transfer && from?.kind == AccountKind.card) {
    found.add(const CardTransferOut());
  }
  if (transfer && e.fee > 0 && currency != homeCode) {
    found.add(const ForeignTransferFee());
  }
  if (to != null && to.kind == AccountKind.card && e.fee > 0) {
    found.add(const CardPaymentFee());
  }
  if (to != null && to.currency != currency && e.received == null) {
    found.add(const MissingReceivedAmount());
  }
  if (to != null && currency != homeCode && to.kind == AccountKind.card) {
    found.add(const ForeignCardPayment());
  }
  if (e.isInvestment && currency != homeCode) {
    found.add(const ForeignInvestment());
  }
  if (e.isInvestment && (from?.kind.isDebt ?? false)) {
    found.add(const InvestmentFromDebt());
  }
  final held = facts.heldBefore;
  if (e.isReduction && held != null && -e.shares > held) {
    found.add(ReductionExceedsHolding(held));
  }
  if (e.type == EntryType.dividend && !e.isReduction && e.tax > e.amount) {
    found.add(const TaxExceedsDividend());
  }
  if (e.isInvestment && e.holding == null) found.add(const MissingHolding());
  if (trade && e.shares <= 0) found.add(const MissingShares());
  if ((e.type == EntryType.sell || e.isReduction) && facts.oversells) {
    found.add(const SaleExceedsHolding());
  }
  final refunded = facts.refunded;
  if (refunded != null &&
      refunded.kind == AccountKind.card &&
      e.account != refunded.account) {
    found.add(const RefundToOtherAccount());
  }
  if (refunded != null && e.amount > refunded.left + refunded.own) {
    found.add(RefundExceedsRemaining(refunded.left));
  }
  found.addAll(_splitIssues(e));
  if (e.installments < 0 || e.installments > maxInstallments) {
    found.add(const InstallmentsOutOfRange(maxInstallments));
  }
  if (e.installments > 1 &&
      (e.type != EntryType.expense || from?.kind != AccountKind.card)) {
    found.add(const InstallmentsOffCard());
  }
  final after = facts.balanceAfter;
  if (e.type == EntryType.buy &&
      after != null &&
      after < 0 &&
      !(from?.kind.isDebt ?? false)) {
    found.add(NegativeBalanceAfter(after));
  }
  return found;
}

/// What a record read back from elsewhere, such as a backup, must be
/// before the ledger can work with it at all, whatever the book around
/// it: the rules of [entryIssues] that need no facts and that no version
/// of the app ever let through. An old record that a newer rule would
/// refuse on writing still reads.
List<RecordIssue> entryShapeIssues(Entry e) => [
  if (!_isMidnight(e.date)) const DateNotMidnight(),
  if (e.amount < 0) const MissingAmount(trade: false),
  if (e.fee < 0 || e.tax < 0) const NegativeCharge(),
  if (e.type == EntryType.transfer && (e.to ?? '').isEmpty)
    const MissingDestination(),
  if (e.installments < 0 || e.installments > maxInstallments)
    const InstallmentsOutOfRange(maxInstallments),
];

/// A split's parts: each more than nothing, together the amount.
List<RecordIssue> _splitIssues(Entry e) {
  if (e.parts.isEmpty) return const [];
  var total = 0;
  var positive = true;
  for (final (_, amount) in e.parts) {
    total += amount;
    if (amount <= 0) positive = false;
  }
  return [
    if (!positive) const SplitPartNotPositive(),
    if (total != e.amount) SplitTotalMismatch(e.amount - total),
  ];
}

bool _isMidnight(DateTime d) =>
    d.isUtc &&
    d.hour == 0 &&
    d.minute == 0 &&
    d.second == 0 &&
    d.millisecond == 0 &&
    d.microsecond == 0;
