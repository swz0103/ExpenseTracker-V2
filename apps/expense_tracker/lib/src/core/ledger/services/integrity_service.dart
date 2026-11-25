import '../models/models.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/recurring_repository.dart';
import '../repositories/trash_repository.dart';

/// Where a record naming something the book no longer has was found.
enum RecordKind { entry, trash, recurring }

/// A record that names another the book no longer has. The ledger still
/// adds up, an account it lacks counting as an empty one, but the book is
/// not as it was written and the person should hear of it.
///
/// What it says is only its kind, never a name, an amount or an id, so it
/// can go to the diagnostics log as it is.
sealed class IntegrityProblem implements Exception {
  const IntegrityProblem(this.kind, this.id);

  /// Which kind of record names what is missing.
  final RecordKind kind;

  /// The id of that record.
  final String id;
}

/// A record pays from or into an account the book does not have.
final class MissingAccount extends IntegrityProblem {
  const MissingAccount(super.kind, super.id, this.account);

  /// The account named and not found.
  final String account;

  @override
  String toString() => 'MissingAccount(${kind.name})';
}

/// A refund of an entry the book no longer has.
final class MissingRefundOriginal extends IntegrityProblem {
  const MissingRefundOriginal(super.kind, super.id, this.original);

  /// The entry it refunds, not found.
  final String original;

  @override
  String toString() => 'MissingRefundOriginal(${kind.name})';
}

/// Looks the book over for records that name others it no longer has.
/// Read once when the book is opened; the commands keep a sound book
/// sound, so what this finds came from before a rule, an import or a
/// restore.
final class IntegrityService {
  IntegrityService({
    required this._entries,
    required this._accounts,
    required this._recurring,
    required this._trash,
  });

  final EntryReader _entries;
  final AccountReader _accounts;
  final RecurringReader _recurring;
  final TrashReader _trash;

  /// Every problem found, entries first, then the trash, then recurring
  /// items.
  List<IntegrityProblem> problems() {
    final found = <IntegrityProblem>[];
    // Exception to as-of-today: the integrity check reads every entry written.
    for (final e in _entries.all) {
      _check(e, RecordKind.entry, found);
    }
    for (final t in _trash.all) {
      _check(t.entry, RecordKind.trash, found);
    }
    for (final r in _recurring.all) {
      if (!_accounts.contains(r.account)) {
        found.add(MissingAccount(RecordKind.recurring, r.id, r.account));
      }
    }
    return found;
  }

  /// Adds to [found] what [e] names that the book lacks: its account, then
  /// the one it moves money to, each once, then the entry it refunds.
  /// Read for every entry as the book opens, so nothing is made for an
  /// entry that names nothing missing (review 32 1.4).
  void _check(Entry e, RecordKind kind, List<IntegrityProblem> found) {
    final account = e.account;
    if (!_accounts.contains(account)) {
      found.add(MissingAccount(kind, e.id, account));
    }
    final to = e.to;
    if (to != null && to != account && !_accounts.contains(to)) {
      found.add(MissingAccount(kind, e.id, to));
    }
    final original = e.refundOf;
    // A refund in the trash may name an original deleted with it.
    if (original != null &&
        kind == RecordKind.entry &&
        _entries.byId(original) == null) {
      found.add(MissingRefundOriginal(kind, e.id, original));
    }
  }
}
