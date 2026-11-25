import '../models/models.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/recurring_repository.dart';
import '../repositories/trash_repository.dart';
import '../../diagnostics/app_fault.dart';

/// Where a record naming something the book no longer has was found.
enum RecordKind { entry, trash, recurring }

/// A record that names another the book no longer has. The ledger still
/// adds up, an account it lacks counting as an empty one, but the book is
/// not as it was written and the person should hear of it.
///
/// What it says is only its kind, never a name, an amount or an id, so it
/// can go to the diagnostics log as it is.
sealed class IntegrityProblem implements AppFault {
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
  List<IntegrityProblem> problems() => [
    // Exception to as-of-today: the integrity check reads every entry written.
    for (final e in _entries.all) ..._ofEntry(e, RecordKind.entry),
    for (final t in _trash.all) ..._ofEntry(t.entry, RecordKind.trash),
    for (final r in _recurring.all)
      if (!_accounts.contains(r.account))
        MissingAccount(RecordKind.recurring, r.id, r.account),
  ];

  Iterable<IntegrityProblem> _ofEntry(Entry e, RecordKind kind) sync* {
    for (final account in {e.account, ?e.to}) {
      if (!_accounts.contains(account)) {
        yield MissingAccount(kind, e.id, account);
      }
    }
    final original = e.refundOf;
    // A refund in the trash may name an original deleted with it.
    if (original != null &&
        kind == RecordKind.entry &&
        _entries.byId(original) == null) {
      yield MissingRefundOriginal(kind, e.id, original);
    }
  }
}
