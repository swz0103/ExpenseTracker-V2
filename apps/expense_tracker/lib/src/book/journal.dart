import '../demo/ledger.dart';

/// Where the book is kept between launches. The [Ledger] changes itself
/// first, so the screens answer at once, then passes each change here;
/// when one is refused it reloads what was kept.
abstract interface class Journal {
  /// Everything kept, as a ledger for the screens.
  Future<Ledger> load();

  Future<void> addEntries(List<Entry> entries);

  /// Replaces [before] with [after], keeping the history of the change.
  /// Returns the id the entry has from now on.
  Future<String> replaceEntry(Entry before, Entry after);

  Future<void> removeEntry(Entry entry);

  /// Opens [after] when [before] is null, otherwise changes it.
  Future<void> saveAccount(Account? before, Account after);

  /// Gives [account] the opening balance [opening].
  Future<void> setOpening(Account account, int opening);

  /// An account without entries; it is archived, never erased.
  Future<void> removeAccount(Account account);

  /// Adds [after] when [before] is null, otherwise changes it.
  Future<void> saveCategory(Category? before, Category after);

  Future<void> mergeCategory(Category from, Category into);

  /// Renames the tag or merchant [from] to [to], merges it into [to] when
  /// that exists already, or retires it when [to] is empty.
  Future<void> relabel(String from, String to, {required bool merchant});

  /// Sets the monthly budget of [Budget.category], from this month on.
  Future<void> setBudget(Budget budget);

  /// Drops the budget of [category] from every month.
  Future<void> removeBudget(String category);

  /// Adds [item], or changes the one with its id.
  Future<void> saveRecurring(Recurring item);

  /// Stops [item]; the entries it booked stay.
  Future<void> removeRecurring(Recurring item);
}
