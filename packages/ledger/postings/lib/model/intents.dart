import 'package:kernel/kernel.dart';

// Today's records as intents of the journal. One kind per thing the
// person does; a foreign value and instalments are amendments of a
// spending, an income or a transfer (Slots), not kinds of their own.

/// What an account held before the first record.
final class OpeningBalance extends LedgerIntent {
  const OpeningBalance({
    required super.id,
    required super.seq,
    required this.account,
    required this.amount,
  }) : super(date: Day.beforeAll);

  static const kind = IntentType('accounts.opening');
  final AccountId account;

  /// In the account's own currency; negative for what is owed.
  final int amount;

  @override
  IntentType get type => kind;
}

/// Spending from [account], by category: one part for a plain spending.
final class Spending extends LedgerIntent {
  const Spending({
    required super.id,
    required super.date,
    required super.seq,
    required this.account,
    required this.parts,
    super.amendments,
  });

  static const kind = IntentType('entries.spending');
  final AccountId account;

  /// Each category's account and amount, in [account]'s currency.
  final List<(AccountId, int)> parts;

  @override
  IntentType get type => kind;
}

/// Money into [account] under [category]: income, or a refund giving
/// spending back (its category then a spending one), split as its
/// purchase was when [parts] are given (D65).
final class Earning extends LedgerIntent {
  const Earning({
    required super.id,
    required super.date,
    required super.seq,
    required this.account,
    required this.category,
    required this.amount,
    this.parts = const [],
    super.amendments,
  });

  static const kind = IntentType('entries.earning');
  final AccountId account;
  final AccountId category;
  final int amount;

  /// Each category's account and amount, in [account]'s currency, adding
  /// up to [amount]; empty when the whole is under [category].
  final List<(AccountId, int)> parts;

  @override
  IntentType get type => kind;
}

/// [amount] moved from [from] to [to], the bank's [fee] on top, spent
/// under [feeCategory]: kept with the transfer, so a later change of
/// where fees go does not move old ones.
final class Transfer extends LedgerIntent {
  const Transfer({
    required super.id,
    required super.date,
    required super.seq,
    required this.from,
    required this.to,
    required this.amount,
    this.fee = 0,
    this.feeCategory,
    super.amendments,
  });

  static const kind = IntentType('entries.transfer');
  final AccountId from;
  final AccountId to;
  final int amount;
  final int fee;
  final AccountId? feeCategory;

  @override
  IntentType get type => kind;
}

/// Shares a stock was held with before the first record: [shares] whole
/// shares that cost [cost], with the gain and dividends so far.
final class OpeningPosition extends LedgerIntent {
  const OpeningPosition({
    required super.id,
    required super.seq,
    required this.code,
    required this.shares,
    required this.cost,
    this.realised = 0,
    this.dividends = 0,
  }) : super(date: Day.beforeAll);

  static const kind = IntentType('investments.opening');
  final String code;
  final int shares;
  final int cost;
  final int realised;
  final int dividends;

  @override
  IntentType get type => kind;
}

/// What a trade is, of the stock [code], paid from or into [cash].
sealed class Trade extends LedgerIntent {
  const Trade({
    required super.id,
    required super.date,
    required super.seq,
    required this.cash,
    required this.code,
    required this.gross,
    this.shares = 0,
    this.fee = 0,
    this.tax = 0,
    super.amendments,
  });

  final AccountId cash;
  final String code;
  final int gross;
  final int shares;
  final int fee;
  final int tax;
}

/// [shares] bought for [gross], the broker's [fee] on top.
final class Buy extends Trade {
  const Buy({
    required super.id,
    required super.date,
    required super.seq,
    required super.cash,
    required super.code,
    required super.gross,
    required super.shares,
    super.fee,
    super.amendments,
  });

  static const kind = IntentType('investments.buy');

  @override
  IntentType get type => kind;
}

/// [shares] sold for [gross], less the [fee] and the transaction [tax];
/// costed at the average price when [average], else oldest lots first.
final class Sell extends Trade {
  const Sell({
    required super.id,
    required super.date,
    required super.seq,
    required super.cash,
    required super.code,
    required super.gross,
    required super.shares,
    super.fee,
    super.tax,
    this.average = false,
    super.amendments,
  });

  static const kind = IntentType('investments.sell');
  final bool average;

  @override
  IntentType get type => kind;
}

/// A dividend of [gross] less the premium withheld ([tax]), with
/// [shares] given; with [split], shares from a split; with negative
/// [shares], a capital reduction returning [gross]. [code] is empty for
/// a dividend naming no stock.
final class Dividend extends Trade {
  const Dividend({
    required super.id,
    required super.date,
    required super.seq,
    required super.cash,
    required super.code,
    required super.gross,
    super.shares,
    super.fee,
    super.tax,
    this.split = false,
    super.amendments,
  });

  static const kind = IntentType('investments.dividend');
  final bool split;

  /// A capital reduction: shares taken back, capital returned.
  bool get isReduction => shares < 0;

  @override
  IntentType get type => kind;
}

/// Why an old book's trade is kept out of the holdings.
enum OutOfHoldingsReason {
  /// It sold more shares than were held by then.
  oversold,

  /// It names no stock.
  noStock,
}

/// A trade an old book keeps whose holdings leave it out, as the app
/// reads such a book today: its money moves, its shares do not.
final class OutOfHoldings extends LedgerIntent {
  const OutOfHoldings({
    required super.id,
    required super.date,
    required super.seq,
    required this.cash,
    required this.settlement,
    required this.reason,
    super.amendments,
  });

  static const kind = IntentType('legacy.outOfHoldings');
  final AccountId cash;

  /// What the trade moved on [cash], in the book's currency.
  final int settlement;
  final OutOfHoldingsReason reason;

  @override
  IntentType get type => kind;
}

/// What an amount in another currency is worth, kept under [Slots.fx].
sealed class ForeignValue {
  const ForeignValue();
}

/// The worth: what a foreign spending or income was worth at home, or
/// what a transfer across currencies received.
final class Worth extends ForeignValue {
  const Worth(this.amount);
  final int amount;
}

/// An old book's reading, kept as it is today: the foreign amount counts
/// as the same number in the other currency. Only ever written on
/// purpose for an old record, never a default.
final class SameNumber extends ForeignValue {
  const SameNumber();
}

/// An old book's transfer across currencies with a fee: what it
/// received is known ([received]); its fee, in the sender's currency,
/// counts as the same number at home, as today.
final class ReceivedFeeSameNumber extends ForeignValue {
  const ReceivedFeeSameNumber(this.received);
  final int received;
}
