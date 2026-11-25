import '../cache/topic.dart';
import '../models/models.dart';
import '../persistence/write_batch.dart';
import '../persistence/unit_of_work.dart';
import '../repositories/account_repository.dart';
import '../repositories/budget_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/recurring_repository.dart';
import '../repositories/trash_repository.dart';
import '../services/entry_query_service.dart';
import '../services/entry_validator.dart';
import 'command_context.dart';
import 'entry_bookkeeping.dart';
import 'held_notices.dart';
import 'undo.dart';

/// Changes across many entries at once: a category or an account for
/// those picked, and a tag or a merchant renamed everywhere, each one
/// change with its undo (D82). Reached through `EntryCommands`.
final class EntryBulkEdits {
  EntryBulkEdits({
    required this._context,
    required this._told,
    required this._book,
    required this._replaceAll,
    required this._entries,
    required this._accounts,
    required this._categories,
    required this._budgets,
    required this._recurring,
    required this._trash,
    required this._entryQueries,
    required this._validator,
  });

  final CommandContext _context;
  final HeldNotices _told;
  final EntryBookkeeping _book;

  /// `EntryCommands.replaceAll`: the entries changed, as one change.
  final void Function(List<Entry> entries) _replaceAll;
  final EntryRepository _entries;
  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final BudgetRepository _budgets;
  final RecurringRepository _recurring;
  final TrashRepository _trash;
  final EntryQueryService _entryQueries;
  final EntryValidator _validator;

  /// Puts the spending or income among [entries] under [name]. Splits,
  /// refunds, entries of the other kind and those the ledger would refuse
  /// (kept by an older version, before a rule) keep their own.
  int recategorize(Iterable<Entry> entries, String name) {
    final income = _categories.byName(name).income;
    final changed = [
      for (final e in entries)
        if (EntryBookkeeping.plain(e) &&
            e.parts.isEmpty &&
            e.category != name &&
            (e.type == EntryType.income) == income &&
            _validator.validate(e.withCategory(name), replacing: e) == null)
          e.withCategory(name),
    ];
    _replaceAll(changed);
    return changed.length;
  }

  /// Moves the spending and income among [entries] to [id], an account in
  /// the same currency. Refunded spending and entries the ledger would
  /// refuse there, such as instalment purchases off a card, stay where
  /// they are.
  int moveToAccount(Iterable<Entry> entries, String id) {
    final into = _accounts.resolve(id);
    final moved = <Entry>[];
    for (final e in [...entries]) {
      if (!EntryBookkeeping.plain(e) || e.account == id) continue;
      if (_accounts.resolve(e.account).currency != into.currency) continue;
      if (e.type == EntryType.expense &&
          _entryQueries.refundable(e) != e.amount) {
        continue;
      }
      // With what was paid in it for others, from the same account.
      final group = [
        (e, e.withAccount(id)),
        for (final m in _entryQueries.groupOf(e))
          if (m.type == EntryType.transfer && m.account == e.account)
            (m, m.withAccount(id)),
      ];
      if (group.any((g) => _book.refusals(g.$2, replacing: g.$1) != null)) {
        continue;
      }
      moved.addAll([for (final (_, next) in group) next]);
    }
    _replaceAll(moved);
    return moved.length;
  }

  /// Renames or merges a tag across every entry; an empty [to] removes it.
  /// The [Undo] puts back the entries and the budgets as they were (D82),
  /// those changed again since left as they are.
  Undo renameTag(String from, String to) {
    final budgets = _budgets.all;
    final book = EntryImages();
    final trash = EntryImages();
    final unit = UnitOfWork();
    if (to.isEmpty) {
      if (_budgets.remove('#$from')) {
        unit.registerDeleted(Collection.budget, '#$from');
      }
    } else {
      final (:removed, :moved) = _budgets.rename('#$from', '#$to');
      if (removed) unit.registerDeleted(Collection.budget, '#$from');
      if (moved != null) unit.registerDirty(moved);
    }
    Entry? retagged(Entry e) => e.tags.contains(from)
        ? e.withLabels(
            tags: {
              for (final t in e.tags)
                if (t != from) t,
              if (to.isNotEmpty) to,
            }.toList(),
          )
        : null;
    unit.registerAllDirty(_entries.changeAll(book.noting(retagged)));
    unit.registerAllDirty(_trash.changeEntries(trash.noting(retagged)));
    final after = _budgets.all;
    _told.changed(Topic.all);
    _context.keep(unit.batch);
    return () {
      final back = UnitOfWork();
      final (:put, :dropped) = _budgets.restore(budgets, after, {
        '#$from',
        if (to.isNotEmpty) '#$to',
      });
      back.registerAllDirty(put);
      for (final key in dropped) {
        back.registerDeleted(Collection.budget, key);
      }
      _putBack(back, book, trash);
    };
  }

  /// Puts the entries [book] and [trash] noted back as they were, with
  /// what [unit] holds, as one change.
  void _putBack(UnitOfWork unit, EntryImages book, EntryImages trash) {
    unit.registerAllDirty(_entries.changeAll(book.back));
    unit.registerAllDirty(_trash.changeEntries(trash.back));
    _told.changed(Topic.all);
    _context.keep(unit.putBack);
  }

  /// Renames or merges a merchant across every entry, and the recurring
  /// items that book it, so the next booking writes the new name; an
  /// empty [to] clears it. The [Undo] puts back the entries and the
  /// recurring items as they were (D82).
  Undo renameMerchant(String from, String to) {
    final book = EntryImages();
    final trash = EntryImages();
    final unit = UnitOfWork();
    Entry? renamed(Entry e) =>
        e.merchant == from ? e.withLabels(merchant: to) : null;
    unit.registerAllDirty(_entries.changeAll(book.noting(renamed)));
    unit.registerAllDirty(_trash.changeEntries(trash.noting(renamed)));
    final before = [
      for (final r in _recurring.all)
        if (r.merchant == from) r,
    ];
    final items = [for (final r in before) r.copyWith(merchant: to)];
    _recurring.replaceExisting(items);
    unit.registerAllDirty(items);
    _told.changed(Topic.all);
    _context.keep(unit.batch);
    return () {
      final back = [
        for (final (i, r) in before.indexed)
          if (identical(_recurring.byId(r.id), items[i])) r,
      ];
      _recurring.replaceExisting(back);
      _putBack(UnitOfWork()..registerAllDirty(back), book, trash);
    };
  }
}
