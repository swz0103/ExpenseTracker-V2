import '../models/models.dart';

/// The kinds of record a [WriteBatch] carries, each kept by its own key: an
/// account, entry, category or recurring item by id, a budget
/// by what it covers, a deleted entry and a receipt by the entry's id.
enum Collection { account, category, entry, budget, recurring, trash, receipt }

/// The records one change of the ledger put in place, and those it
/// took away.
final class WriteBatch {
  WriteBatch({
    this.accounts = const [],
    this.categories = const [],
    this.entries = const [],
    this.budgets = const [],
    this.recurring = const [],
    this.trash = const [],
    this.receipts = const {},
    this.dropped = const [],
    this.drafts = const {},
    this.putBack = false,
  });

  /// Whether the change is an undo putting back what one just before took
  /// away (D82): each record it keeps that was taken away this run goes
  /// back to the place it stood in the order kept, so it stands there
  /// still once the book is opened again (D119). Anything else taken away
  /// and kept anew comes last.
  final bool putBack;

  final List<Account> accounts;
  final List<Category> categories;
  final List<Entry> entries;
  final List<Budget> budgets;
  final List<Recurring> recurring;
  final List<Trashed> trash;

  /// Each entry's receipt photo, by entry id; null takes it away.
  final Map<String, String?> receipts;

  /// Records taken away, by collection and key.
  final List<(Collection, String)> dropped;

  /// Forms put aside in the composer, as JSON by tab; null clears one.
  /// Kept like the records, but not a change of the book.
  final Map<String, String?> drafts;

  /// Only drafts: nothing a backup need be taken for.
  bool get onlyDrafts =>
      drafts.isNotEmpty &&
      accounts.isEmpty &&
      categories.isEmpty &&
      entries.isEmpty &&
      budgets.isEmpty &&
      recurring.isEmpty &&
      trash.isEmpty &&
      receipts.isEmpty &&
      dropped.isEmpty;

  bool get isEmpty =>
      accounts.isEmpty &&
      categories.isEmpty &&
      entries.isEmpty &&
      budgets.isEmpty &&
      recurring.isEmpty &&
      trash.isEmpty &&
      receipts.isEmpty &&
      dropped.isEmpty &&
      drafts.isEmpty;
}
