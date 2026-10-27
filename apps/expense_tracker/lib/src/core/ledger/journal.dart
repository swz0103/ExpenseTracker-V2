import 'ledger.dart';

/// Where the book is kept between launches. The [Ledger] changes itself
/// first, so the screens answer at once, then hands each change here as a
/// [Batch]; when one cannot be kept it reads back what was.
abstract interface class Journal {
  /// Everything kept, as a ledger for the screens.
  Future<Ledger> load();

  /// Keeps every record of [batch] and forgets the dropped ones, all
  /// together or, when this throws, none of them.
  Future<void> keep(Batch batch);
}

/// The [Journal] could not keep a change: its file is closed, locked or
/// cannot be written.
final class JournalFailure implements Exception {
  const JournalFailure(this.cause);

  final Object cause;

  @override
  String toString() => 'JournalFailure($cause)';
}

/// The kinds of record a [Batch] carries, each kept by its own key: an
/// account, entry or recurring item by id, a category by name, a budget
/// by what it covers, a deleted entry and a receipt by the entry's id.
enum Shelf { account, category, entry, budget, recurring, trash, receipt }

/// The records one change of the [Ledger] put in place, and those it
/// took away.
final class Batch {
  Batch({
    this.accounts = const [],
    this.categories = const [],
    this.entries = const [],
    this.budgets = const [],
    this.recurring = const [],
    this.trash = const [],
    this.receipts = const {},
    this.dropped = const [],
  });

  final List<Account> accounts;
  final List<Category> categories;
  final List<Entry> entries;
  final List<Budget> budgets;
  final List<Recurring> recurring;
  final List<Trashed> trash;

  /// Each entry's receipt photo, by entry id; null takes it away.
  final Map<String, String?> receipts;

  /// Records taken away, by shelf and key.
  final List<(Shelf, String)> dropped;

  bool get isEmpty =>
      accounts.isEmpty &&
      categories.isEmpty &&
      entries.isEmpty &&
      budgets.isEmpty &&
      recurring.isEmpty &&
      trash.isEmpty &&
      receipts.isEmpty &&
      dropped.isEmpty;
}
