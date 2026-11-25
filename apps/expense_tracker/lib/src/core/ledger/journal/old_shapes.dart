/// Shapes of records an older book (or today's, for a few) keeps whose
/// meaning the journal makes visible and nobody has decided yet. Each is
/// posted in an explicit, recorded form that keeps every figure the app
/// shows today, and counted, so the owner can decide with the numbers.
enum OldShape {
  /// Spending or income in a foreign account with no worth at home:
  /// today its foreign amount counts as the same number of NT$. Posted
  /// with the foreign value `SameNumber`.
  foreignWithoutHome,

  /// A transfer between currencies that does not say what arrived: today
  /// the same number arrives. Posted with `SameNumber`.
  crossCurrencyWithoutReceived,

  /// Income (not a refund) under a spending category: today it counts as
  /// income. Posted to that name's income account.
  incomeUnderSpendingCategory,

  /// Spending, or a refund, under an income category: today it counts as
  /// spending under that name. Posted to that name's spending account.
  spendingUnderIncomeCategory,

  /// A transfer whose fee is paid in a foreign currency: today the fee's
  /// number counts as NT$ of spending. Posted with `SameNumber` (or
  /// `ReceivedFeeSameNumber` when what arrived is known).
  foreignTransferFee,

  /// A sale or a capital reduction taking more shares than were held,
  /// kept by an older version: today the holdings leave it out and its
  /// money still moves. Posted as `OutOfHoldings`.
  oversoldTrade,

  /// A buy, sale or reduction naming no stock: as [oversoldTrade].
  tradeWithoutStock,

  /// A trade paid from or into a foreign account: today its NT$ figures
  /// move the foreign account by the same number. Posted with
  /// `SameNumber`.
  foreignTrade,

  /// A record naming an account the book does not keep: today it is read
  /// as an empty NT$ bank account, counted nowhere. Posted to an account
  /// of its own, outside net worth.
  missingAccount,

  /// A purchase in instalments on an account that is not a card: today
  /// it is billed by that account's billing days all the same. Posted
  /// with the instalments amendment, as on a card.
  instalmentsOffCard,
}
