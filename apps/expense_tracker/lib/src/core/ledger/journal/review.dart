import '../models/models.dart';
import 'book_mapping.dart';
import 'old_shapes.dart';

/// A record whose shape the journal makes visible and the person should
/// look at: its figures are kept as the app shows them today, nothing is
/// changed for it (decision D47). One kind per [OldShape].
sealed class NeedsReview {
  const NeedsReview(this.record);

  /// The record's id.
  final String record;

  /// The old shape it has.
  OldShape get shape;

  @override
  bool operator ==(Object other) =>
      other is NeedsReview &&
      other.runtimeType == runtimeType &&
      other.record == record;

  @override
  int get hashCode => Object.hash(runtimeType, record);

  @override
  String toString() => '${shape.name}($record)';
}

/// Spending or income in a foreign account with no worth at home.
final class NoWorthAtHome extends NeedsReview {
  const NoWorthAtHome(super.record);
  @override
  OldShape get shape => OldShape.foreignWithoutHome;
}

/// A transfer between currencies that does not say what arrived.
final class NothingReceived extends NeedsReview {
  const NothingReceived(super.record);
  @override
  OldShape get shape => OldShape.crossCurrencyWithoutReceived;
}

/// Income kept under a spending category.
final class IncomeUnderSpending extends NeedsReview {
  const IncomeUnderSpending(super.record);
  @override
  OldShape get shape => OldShape.incomeUnderSpendingCategory;
}

/// Spending, or a refund, kept under an income category.
final class SpendingUnderIncome extends NeedsReview {
  const SpendingUnderIncome(super.record);
  @override
  OldShape get shape => OldShape.spendingUnderIncomeCategory;
}

/// A transfer whose fee is paid in a foreign currency.
final class ForeignFee extends NeedsReview {
  const ForeignFee(super.record);
  @override
  OldShape get shape => OldShape.foreignTransferFee;
}

/// A sale or reduction taking more shares than were held.
final class Oversold extends NeedsReview {
  const Oversold(super.record);
  @override
  OldShape get shape => OldShape.oversoldTrade;
}

/// A buy, sale or reduction naming no stock.
final class NoStock extends NeedsReview {
  const NoStock(super.record);
  @override
  OldShape get shape => OldShape.tradeWithoutStock;
}

/// A trade paid from or into a foreign account.
final class ForeignTrade extends NeedsReview {
  const ForeignTrade(super.record);
  @override
  OldShape get shape => OldShape.foreignTrade;
}

/// A record naming an account the book does not keep.
final class NoSuchAccount extends NeedsReview {
  const NoSuchAccount(super.record);
  @override
  OldShape get shape => OldShape.missingAccount;
}

/// A purchase in instalments on an account that is not a card.
final class InstalmentsOffCard extends NeedsReview {
  const InstalmentsOffCard(super.record);
  @override
  OldShape get shape => OldShape.instalmentsOffCard;
}

/// The reason [record] needs looking at for [shape].
NeedsReview _reviewOf(OldShape shape, String record) => switch (shape) {
  OldShape.foreignWithoutHome => NoWorthAtHome(record),
  OldShape.crossCurrencyWithoutReceived => NothingReceived(record),
  OldShape.incomeUnderSpendingCategory => IncomeUnderSpending(record),
  OldShape.spendingUnderIncomeCategory => SpendingUnderIncome(record),
  OldShape.foreignTransferFee => ForeignFee(record),
  OldShape.oversoldTrade => Oversold(record),
  OldShape.tradeWithoutStock => NoStock(record),
  OldShape.foreignTrade => ForeignTrade(record),
  OldShape.missingAccount => NoSuchAccount(record),
  OldShape.instalmentsOffCard => InstalmentsOffCard(record),
};

/// Every record of [entries] in an old shape, in the order kept, each
/// reason once: read off each record as the journal maps it, and off the
/// trades the holdings leave out ([leftOut], `HoldingRepository`). Pure
/// and in one pass, so a screen may ask it, or ask it on an isolate.
List<NeedsReview> recordsNeedingReview({
  required List<Entry> entries,
  required Iterable<Account> accounts,
  required Iterable<Category> categories,
  List<String> leftOut = const [],
}) {
  final mapping = BookMapping(accounts: accounts, categories: categories);
  final out = {for (final id in leftOut) id};
  return [
    for (final (i, e) in entries.indexed) ...[
      for (final shape in mapping.map(e, i).shapes) _reviewOf(shape, e.id),
      if (out.contains(e.id)) Oversold(e.id),
    ],
  ];
}
