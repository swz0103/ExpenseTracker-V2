import '../models/models.dart';
import 'write_batch.dart';

/// What one change of the ledger touched, gathered as it goes and handed
/// to the data source as one [WriteBatch] (Fowler, *Patterns of
/// Enterprise Application Architecture*: Unit of Work).
///
/// A record registered twice is written once, as it ended; one registered
/// as deleted after it was changed is only dropped, and one changed again
/// after it was deleted is only written.
final class UnitOfWork {
  final _entries = <String, Entry>{};
  final _categories = <String, Category>{};
  final _budgets = <String, Budget>{};
  final _recurring = <String, Recurring>{};
  final _trash = <String, Trashed>{};
  final _deleted = <(Collection, String)>{};

  /// Registers [record], new or changed, to be written: an [Entry], a
  /// [Category], a [Budget], a [Recurring] item or a [Trashed] entry.
  void registerDirty(Object record) {
    final (collection, key) = switch (record) {
      Entry e => (Collection.entry, e.id),
      Category c => (Collection.category, c.id),
      Budget b => (Collection.budget, b.category),
      Recurring r => (Collection.recurring, r.id),
      Trashed t => (Collection.trash, t.entry.id),
      _ => throw ArgumentError.value(record, 'record', 'not a record kept'),
    };
    _deleted.remove((collection, key));
    switch (record) {
      case Entry e:
        _entries[key] = e;
      case Category c:
        _categories[key] = c;
      case Budget b:
        _budgets[key] = b;
      case Recurring r:
        _recurring[key] = r;
      case Trashed t:
        _trash[key] = t;
    }
  }

  /// Registers each of [records] as [registerDirty] does.
  void registerAllDirty(Iterable<Object> records) =>
      records.forEach(registerDirty);

  /// Registers the record of [collection] kept under [key] to be dropped.
  void registerDeleted(Collection collection, String key) {
    switch (collection) {
      case Collection.entry:
        _entries.remove(key);
      case Collection.category:
        _categories.remove(key);
      case Collection.budget:
        _budgets.remove(key);
      case Collection.recurring:
        _recurring.remove(key);
      case Collection.trash:
        _trash.remove(key);
      case Collection.account || Collection.receipt:
        break;
    }
    _deleted.add((collection, key));
  }

  /// Whether nothing was registered.
  bool get isEmpty =>
      _entries.isEmpty &&
      _categories.isEmpty &&
      _budgets.isEmpty &&
      _recurring.isEmpty &&
      _trash.isEmpty &&
      _deleted.isEmpty;

  /// Everything registered, in the order first registered.
  WriteBatch get batch => _batch();

  /// Everything registered, as an undo puts it back: each record taken
  /// away by the change it undoes back in its place ([WriteBatch.putBack]).
  WriteBatch get putBack => _batch(putBack: true);

  WriteBatch _batch({bool putBack = false}) => WriteBatch(
    entries: [..._entries.values],
    categories: [..._categories.values],
    budgets: [..._budgets.values],
    recurring: [..._recurring.values],
    trash: [..._trash.values],
    dropped: [..._deleted],
    putBack: putBack,
  );
}
