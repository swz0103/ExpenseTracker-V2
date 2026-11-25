import 'package:ledger_entries/rules.dart'
    show EntryDeleted, SaleExceedsHolding;

import '../cache/topic.dart';
import '../models/models.dart';
import '../persistence/write_batch.dart';
import '../repositories/account_repository.dart';
import '../repositories/budget_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/holding_repository.dart';
import '../repositories/receipt_repository.dart';
import '../repositories/recurring_repository.dart';
import '../repositories/trash_repository.dart';
import '../services/entry_query_service.dart';
import '../services/entry_validator.dart';
import '../services/recurring_service.dart';
import 'command_context.dart';
import 'command_exceptions.dart';
import 'entry_bookkeeping.dart';
import 'entry_bulk_edits.dart';
import 'held_notices.dart';
import 'restore_hold.dart';
import 'trash_commands.dart';
import 'undo.dart';

export 'restore_hold.dart';

/// Writes the entries: adding, changing, removing and bringing them back,
/// one at a time, as a group or many at once; each change is kept as one
/// batch. Nothing is written that the ledger's write rules refuse
/// ([EntryValidator]), whoever writes it: [add], [save], [addAll],
/// [replaceAll] and the rest throw a [RecordRefused] before anything
/// changes, a sale left short of shares included ([SaleExceedsHolding]).
/// Taking entries away and bringing them back, which undo and the trash
/// do with no form to answer, tell the same problems through
/// [CommandContext.problem] instead.
///
/// The trash's own changes ([TrashCommands]) and the changes across many
/// entries ([EntryBulkEdits]) are kept apart and reached through here;
/// all of them share one [EntryBookkeeping] of what a refusal undoes and
/// of the recurring days a deletion lets go.
final class EntryCommands {
  EntryCommands({
    required this._context,
    required EntryRepository entryRepository,
    required AccountRepository accountRepository,
    required CategoryRepository categoryRepository,
    required HoldingRepository holdingRepository,
    required RecurringRepository recurringRepository,
    required BudgetRepository budgetRepository,
    required TrashRepository trashRepository,
    required ReceiptRepository receiptRepository,
    required this._recurringService,
    required EntryQueryService entryQueryService,
    required EntryValidator entryValidator,
  }) : _entries = entryRepository,
       _accounts = accountRepository,
       _categories = categoryRepository,
       _holdings = holdingRepository,
       _recurring = recurringRepository,
       _budgets = budgetRepository,
       _trash = trashRepository,
       _receipts = receiptRepository,
       _entryQueries = entryQueryService,
       _validator = entryValidator;

  final CommandContext _context;

  /// The screens told through [_context], once for each putting back.
  late final _told = HeldNotices(_context);
  final EntryRepository _entries;
  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final HoldingRepository _holdings;
  final RecurringRepository _recurring;
  final BudgetRepository _budgets;
  final TrashRepository _trash;
  final ReceiptRepository _receipts;
  final RecurringService _recurringService;
  final EntryQueryService _entryQueries;
  final EntryValidator _validator;

  /// Adds [entry], with its receipt photo [receipt] when one is given.
  void add(Entry entry, {String? receipt}) =>
      save([entry], receipt: receipt, receiptOn: entry.id);

  /// Adds [settlement], the transfer that settles [account] before it is
  /// archived: dated on the day of [account]'s last entry, which it may
  /// be however far ahead (D120, D121), the one entry the write rules let
  /// beyond the year ahead.
  void addSettlement(Entry settlement, String account) =>
      save([settlement], settling: account);

  /// Adds every one of [entries] at once, with the [accounts] and
  /// [categories] they bring, as an import does: all of it is kept
  /// together, or none. The [Undo] takes it back again (D82): the
  /// entries, not to the trash, and the accounts and categories added
  /// that nothing names by then.
  Undo addAll(
    List<Entry> entries, {
    List<Account> accounts = const [],
    List<Category> categories = const [],
  }) {
    if (entries.isEmpty && accounts.isEmpty && categories.isEmpty) {
      return () {};
    }
    entries = EntryBookkeeping.kept(entries);
    _book.check(entries, opening: accounts);
    final count = _entries.length;
    _entries.addAll(entries);
    _book.replayOrUndo(
      () => _entries.removeRange(count, _entries.length),
      trades: entries.any((e) => e.isInvestment),
    );
    final seen = <String>{};
    final named = [
      for (final c in categories)
        if (_categories.isNameFree(c.name) && seen.add(c.name.trim()))
          CategoryRepository.trimmed(c),
    ];
    final opened = _accounts.addNew(accounts);
    _categories.addAll(named);
    _told.changed(Topic.all);
    _context.keep(
      WriteBatch(accounts: opened, categories: named, entries: entries),
    );
    final added = entries;
    return () => _told.quietly(() {
      if (!takeBack(added)) return;
      _dropUnnamed(opened, named);
    });
  }

  /// Takes [added] out of the book, not to the trash, as one change: what
  /// taking back their adding does. An entry goes only while the book
  /// holds that very one (a change since leaves it, as [EntryImages]
  /// does), and while no refund left in the book names it as its
  /// purchase; how many of [added] stay in the book for that is told
  /// through [CommandContext.problem] as a [StayedInBook]. False, with
  /// nothing changed, when none goes, or when it would leave a later
  /// sale short of shares (told the same way).
  bool takeBack(Iterable<Entry> added) => _told.quietly(() {
    final held = {
      for (final e in added)
        if (_entries.byId(e.id) case final now?) e.id: (e, now),
    };
    final going = {
      for (final MapEntry(key: id, value: (e, now)) in held.entries)
        if (identical(e, now)) id,
    };
    // A refund the book keeps keeps its purchase.
    going.removeAll([
      for (final id in going)
        if (_entries.refundsOf(id).any((r) => !going.contains(r.id))) id,
    ]);
    final stayed = held.length - going.length;
    if (going.isEmpty) {
      if (stayed > 0) _told.report(StayedInBook(stayed));
      return false;
    }
    final removed = _entries.removeEach([for (final id in going) held[id]!.$1]);
    if (!_book.tryReplay(() {
      for (final (i, e) in removed) {
        _entries.insert(i, e);
      }
    }, trades: removed.any((r) => r.$2.isInvestment))) {
      return false;
    }
    _context.keep(
      WriteBatch(
        dropped: [for (final (_, e) in removed) (Collection.entry, e.id)],
      ),
    );
    if (stayed > 0) _told.report(StayedInBook(stayed));
    return true;
  });

  /// Takes away those of [accounts] and [categories] that no entry, in
  /// the book or the trash, and no recurring item names.
  void _dropUnnamed(List<Account> accounts, List<Category> categories) {
    if (accounts.isEmpty && categories.isEmpty) return;
    final named = <String>{};
    void note(Entry e) => named.addAll([
      e.account,
      ?e.to,
      e.category,
      for (final (name, _) in e.parts) name,
    ]);
    // Exception to as-of-today: an entry of any day may name them.
    _entries.all.forEach(note);
    for (final t in _trash.all) {
      note(t.entry);
    }
    for (final r in _recurring.all) {
      named.addAll([r.account, r.category]);
    }
    final dropped = <(Collection, String)>[];
    for (final a in accounts) {
      if (named.contains(a.id) || _accounts.remove(a.id) == null) continue;
      dropped.add((Collection.account, a.id));
    }
    for (final c in categories) {
      if (named.contains(c.name)) continue;
      final (:removed, freed: _) = _categories.removeMerged(c.name);
      if (removed != null) dropped.add((Collection.category, removed.id));
    }
    if (dropped.isEmpty) return;
    _told.changed(Topic.all);
    _context.keep(WriteBatch(dropped: dropped));
  }

  /// Puts [entry] in place of the entry with the same id, with the receipt
  /// photo [receipt] (null takes it away).
  void replace(Entry entry, {String? receipt}) => save(
    [entry],
    replacing: [entry.id],
    receipt: receipt,
    receiptOn: entry.id,
  );

  /// Puts each of [entries] in place of the one with the same id, as one
  /// change; those the ledger does not hold are left out.
  void replaceAll(List<Entry> entries) {
    entries = EntryBookkeeping.kept(entries);
    _book.check(entries, replacing: entries.map((e) => e.id));
    final before = <int, Entry>{};
    for (final e in entries) {
      final index = _entries.indexWhere((x) => x.id == e.id);
      if (index < 0) continue;
      before.putIfAbsent(index, () => _entries[index]);
      _entries[index] = e;
    }
    if (before.isEmpty) return;
    _book.replayOrUndo(() {
      for (final MapEntry(key: index, value: e) in before.entries) {
        _entries[index] = e;
      }
    }, trades: [...before.values, ...entries].any((e) => e.isInvestment));
    _context.keep(
      WriteBatch(entries: [for (final i in before.keys) _entries[i]]),
    );
  }

  /// Keeps what a form wrote: [entries], written as one, in place of the
  /// entries [replacing] held (none for a new entry). Those kept are
  /// changed, new ones added and the rest taken away (not to the trash:
  /// they are part of the same change), with the receipt photo [receipt]
  /// on [receiptOn], all in one batch.
  void save(
    List<Entry> entries, {
    Iterable<String> replacing = const [],
    String? receipt,
    String? receiptOn,
    String? settling,
  }) {
    final was = {...replacing};
    // An entry deleted while its form was open is not brought back as a
    // second copy beside the one in the trash (D78).
    if (was.any((id) => _entries.byId(id) == null && _trash.holds(id))) {
      throw RecordRefused(const [EntryDeleted()]);
    }
    entries = EntryBookkeeping.kept(entries);
    _book.check(entries, replacing: was, settling: settling);
    final ids = {for (final e in entries) e.id};
    final gone = {...was}..removeAll(ids);
    // Each change made one entry at a time, which the entries' indexes
    // follow (a change of the whole list would throw them away and every
    // balance with them), noted so that a refusal undoes exactly it. A
    // new entry is found absent by id, without a pass over the book.
    final undo = <void Function()>[];
    var trades = entries.any((e) => e.isInvestment);
    for (final id in gone) {
      final old = _entries.byId(id);
      if (old == null) continue;
      trades |= old.isInvestment;
      final index = _entries.indexOf(old);
      _entries.removeAt(index);
      undo.add(() => _entries.insert(index, old));
    }
    for (final e in entries) {
      final old = _entries.byId(e.id);
      if (old == null) {
        _entries.add(e);
        undo.add(() => _entries.remove(e));
      } else {
        trades |= old.isInvestment;
        final index = _entries.indexOf(old);
        _entries[index] = e;
        undo.add(() => _entries[index] = old);
      }
    }
    _book.replayOrUndo(() {
      for (final step in undo.reversed) {
        step();
      }
    }, trades: trades);
    final photos = <String, String?>{};
    for (final id in {...was, ...ids}) {
      final now = id == receiptOn ? receipt : null;
      if (!_receipts.set(id, now)) continue;
      photos[id] = now;
    }
    _context.keep(
      WriteBatch(
        entries: entries,
        receipts: photos,
        dropped: [for (final id in gone) (Collection.entry, id)],
      ),
    );
  }

  /// Removes the entry with [id] and returns it, for undo. Null when
  /// there is none, or when taking it away would leave a later sale short
  /// of shares: that is told through [CommandContext.problem].
  Entry? remove(String id) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return null;
    // Its period, worked out while it still counts.
    final (skipping, letGo) = _book.skipping([_entries[index]]);
    final removed = _entries.removeAt(index);
    if (!_book.tryReplay(
      () => _entries.insert(index, removed),
      trades: removed.isInvestment,
    )) {
      return null;
    }
    _recurring.replaceExisting(skipping);
    final trashed = Trashed(
      removed,
      _context.today,
      order: _entries.orderOf(removed.id),
      letGo: letGo[removed.id],
    );
    _trash.put(trashed);
    _context.keep(
      WriteBatch(
        trash: [trashed],
        recurring: skipping,
        dropped: [(Collection.entry, removed.id)],
      ),
    );
    if (skipping.isNotEmpty) _told.changed(const {Topic.recurring});
    return removed;
  }

  /// Removes every entry of [ids] as one change, and returns them, for
  /// undo; none when taking them away would leave a later sale short of
  /// shares, which is told through [CommandContext.problem].
  List<Entry> removeAll(Iterable<String> ids) {
    // Found by id and taken away one by one, which the entries' indexes
    // follow: the balances of the accounts left untouched stand.
    final found = [
      for (final id in {...ids}) ?_entries.byId(id),
    ];
    if (found.isEmpty) return const [];
    final (skipping, letGo) = _book.skipping(_entries.written(found));
    final removed = _entries.removeEach(found);
    if (!_book.tryReplay(() {
      for (final (i, e) in removed) {
        _entries.insert(i, e);
      }
    }, trades: removed.any((r) => r.$2.isInvestment))) {
      return const [];
    }
    _recurring.replaceExisting(skipping);
    final trashed = [
      for (final (_, e) in removed)
        Trashed(
          e,
          _context.today,
          order: _entries.orderOf(e.id),
          letGo: letGo[e.id],
        ),
    ];
    _trash.putAll(trashed);
    _context.keep(
      WriteBatch(
        trash: trashed,
        recurring: skipping,
        dropped: [for (final (_, e) in removed) (Collection.entry, e.id)],
      ),
    );
    if (skipping.isNotEmpty) _told.changed(const {Topic.recurring});
    return [for (final (_, e) in removed) e];
  }

  /// Puts back what [removeAll] took away, as one change, the screens
  /// told once it is done. Entries something now stands in the way of
  /// ([_heldBack]: an account closed since, a refund's purchase not in the
  /// book) stay in the trash, to be put back there one by one, with their
  /// whole group and refund or purchase, told through
  /// [CommandContext.problem] as a [StayedInTrash]. True when every entry
  /// is back; false when any is not, or when it no longer fits the trades
  /// kept since (told the same way, nothing put back).
  bool restoreAll(List<Entry> removed) {
    if (removed.isEmpty) return true;
    return _told.quietly(() => _restoreAll(removed));
  }

  bool _restoreAll(List<Entry> all) {
    final every = {for (final e in all) e.id};
    if (_entries.any((e) => every.contains(e.id))) return false;
    final held = _heldBack(all);
    final removed = [
      for (final e in all)
        if (!held.contains(e.id)) e,
    ];
    if (removed.isEmpty) {
      _told.report(StayedInTrash(held.length));
      return false;
    }
    final ids = {for (final e in removed) e.id};
    if (!_book.tryCheck(removed)) return false;
    // Back in its own place (D75), where the data source keeps it too.
    for (final e in removed) {
      _entries.restoreAt(e, _entries.orderOf(e.id));
    }
    if (!_book.tryReplay(
      () => _entries.removeWhere((e) => ids.contains(e.id)),
      trades: removed.any((e) => e.isInvestment),
    )) {
      return false;
    }
    final back = _book.unskipping(removed, _book.letGoOf(ids));
    _trash.removeEntries(ids);
    _recurring.replaceExisting(back);
    _context.keep(
      WriteBatch(
        entries: removed,
        recurring: back,
        dropped: [for (final id in ids) (Collection.trash, id)],
      ),
    );
    if (back.isNotEmpty) _told.changed(const {Topic.recurring});
    if (held.isNotEmpty) _told.report(StayedInTrash(held.length));
    return held.isEmpty;
  }

  /// Puts back an entry [remove] took away, the screens told once it is
  /// done. False, told through [CommandContext.problem], when it no longer
  /// fits the trades kept since, or when something now stands in its way
  /// ([_heldBack]): then it stays in the trash ([StayedInTrash]).
  bool restore(Entry entry) => _told.quietly(() => _restore(entry));

  bool _restore(Entry entry) {
    if (_entries.byId(entry.id) != null) return false;
    if (_heldBack([entry]).isNotEmpty) {
      _told.report(StayedInTrash(1));
      return false;
    }
    if (!_book.tryCheck([entry])) return false;
    // Back in its own place, as in [restoreAll].
    _entries.restoreAt(entry, _entries.orderOf(entry.id));
    if (!_book.tryReplay(
      () => _entries.remove(entry),
      trades: entry.isInvestment,
    )) {
      return false;
    }
    final back = _book.unskipping([entry], _book.letGoOf({entry.id}));
    _trash.removeEntries({entry.id});
    _recurring.replaceExisting(back);
    _context.keep(
      WriteBatch(
        entries: [entry],
        recurring: back,
        dropped: [(Collection.trash, entry.id)],
      ),
    );
    if (back.isNotEmpty) _told.changed(const {Topic.recurring});
    return true;
  }

  /// Of [back], put back together by an undo, the ids of those that must
  /// stay in the trash: each naming an account closed since, or a refund
  /// whose purchase is neither in the book nor among [back]; and with them
  /// the rest of their group and the refunds and purchases they make a
  /// pair with among [back], which come back together or not at all.
  Set<String> _heldBack(List<Entry> back) {
    final ids = {for (final e in back) e.id};
    bool closed(String id) => _accounts.byId(id)?.archived ?? false;
    final held = {
      for (final e in back)
        if ({e.account, ?e.to}.any(closed) ||
            (e.refundOf != null &&
                !ids.contains(e.refundOf) &&
                _entries.byId(e.refundOf!) == null))
          e.id,
    };
    // Held together: a group, and a refund with its purchase.
    for (var grew = held.isNotEmpty; grew;) {
      grew = false;
      final groups = {
        for (final e in back)
          if (held.contains(e.id)) ?e.group,
      };
      for (final e in back) {
        if (held.contains(e.id)) continue;
        if (groups.contains(e.group) ||
            held.contains(e.refundOf) ||
            back.any((r) => r.refundOf == e.id && held.contains(r.id))) {
          held.add(e.id);
          grew = true;
        }
      }
    }
    return held;
  }

  // ---- the trash and changes across many entries, kept apart ----

  /// What every write here shares: the write rules, the trades replayed
  /// and the recurring days let go.
  late final _book = EntryBookkeeping(
    context: _context,
    told: _told,
    entries: _entries,
    holdings: _holdings,
    recurring: _recurring,
    trash: _trash,
    recurringService: _recurringService,
    validator: _validator,
  );

  late final _trashed = TrashCommands(
    context: _context,
    told: _told,
    book: _book,
    entries: _entries,
    accounts: _accounts,
    holdings: _holdings,
    recurring: _recurring,
    trash: _trash,
    receipts: _receipts,
  );

  late final _bulk = EntryBulkEdits(
    context: _context,
    told: _told,
    book: _book,
    replaceAll: replaceAll,
    entries: _entries,
    accounts: _accounts,
    categories: _categories,
    budgets: _budgets,
    recurring: _recurring,
    trash: _trash,
    entryQueries: _entryQueries,
    validator: _validator,
  );

  /// [TrashCommands.holdsOf].
  List<RestoreHold> holdsOf(Trashed trashed) => _trashed.holdsOf(trashed);

  /// [TrashCommands.restoreTrashed].
  bool restoreTrashed(
    Trashed trashed, {
    bool reopen = false,
    bool withOriginal = false,
  }) => _trashed.restoreTrashed(
    trashed,
    reopen: reopen,
    withOriginal: withOriginal,
  );

  /// [TrashCommands.expireTrash].
  int expireTrash() => _trashed.expireTrash();

  /// [TrashCommands.discardTrashed].
  int discardTrashed(Iterable<Trashed> trashed) =>
      _trashed.discardTrashed(trashed);

  /// [EntryBulkEdits.recategorize].
  int recategorize(Iterable<Entry> entries, String name) =>
      _bulk.recategorize(entries, name);

  /// [EntryBulkEdits.moveToAccount].
  int moveToAccount(Iterable<Entry> entries, String id) =>
      _bulk.moveToAccount(entries, id);

  /// [EntryBulkEdits.renameTag].
  Undo renameTag(String from, String to) => _bulk.renameTag(from, to);

  /// [EntryBulkEdits.renameMerchant].
  Undo renameMerchant(String from, String to) => _bulk.renameMerchant(from, to);
}
