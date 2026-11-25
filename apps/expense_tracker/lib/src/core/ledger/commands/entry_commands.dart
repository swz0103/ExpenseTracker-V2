// Exception to file length: every write of the entries and every way back
// (undo, the trash) share one bookkeeping of what a refusal undoes and of
// the recurring days a deletion lets go; split, each half would need the
// other's.
import 'package:core/constants/retention.dart';
import 'package:ledger_entries/rules.dart'
    show EntryDeleted, RecordIssue, SaleExceedsHolding;

import '../cache/topic.dart';
import '../models/models.dart';
import '../persistence/write_batch.dart';
import '../portfolio.dart' show OversoldTrade;
import '../persistence/unit_of_work.dart';
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
import 'held_notices.dart';
import 'restore_hold.dart';
import 'undo.dart';

export 'restore_hold.dart';

/// Writes the entries: adding, changing, removing and bringing them back,
/// one at a time, as a group or many at once; each change is kept as one
/// batch. Nothing is written that the ledger's write rules refuse
/// ([EntryValidator]), whoever writes it: [add], [save], [addAll],
/// [replaceAll] and the rest throw a [RecordRefused] before anything
/// changes, a sale left short of shares included ([SaleExceedsHolding]). Taking entries away and bringing them back, which undo and the
/// trash do with no form to answer, tell the same problems through
/// [CommandContext.problem] instead.
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
    entries = _kept(entries);
    _check(entries, opening: accounts);
    final count = _entries.length;
    _entries.addAll(entries);
    _replayOrUndo(
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
    if (!_tryReplay(() {
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
    entries = _kept(entries);
    _check(entries, replacing: entries.map((e) => e.id));
    final before = <int, Entry>{};
    for (final e in entries) {
      final index = _entries.indexWhere((x) => x.id == e.id);
      if (index < 0) continue;
      before.putIfAbsent(index, () => _entries[index]);
      _entries[index] = e;
    }
    if (before.isEmpty) return;
    _replayOrUndo(() {
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
  }) {
    final was = {...replacing};
    // An entry deleted while its form was open is not brought back as a
    // second copy beside the one in the trash (D78).
    if (was.any((id) => _entries.byId(id) == null && _trash.holds(id))) {
      throw RecordRefused(const [EntryDeleted()]);
    }
    entries = _kept(entries);
    _check(entries, replacing: was);
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
    _replayOrUndo(() {
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
    final (skipping, letGo) = _skipping([_entries[index]]);
    final removed = _entries.removeAt(index);
    if (!_tryReplay(
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
    final (skipping, letGo) = _skipping(_entries.written(found));
    final removed = _entries.removeEach(found);
    if (!_tryReplay(() {
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
    if (!_tryCheck(removed)) return false;
    // Back in its own place (D75), where the data source keeps it too.
    for (final e in removed) {
      _entries.restoreAt(e, _entries.orderOf(e.id));
    }
    if (!_tryReplay(
      () => _entries.removeWhere((e) => ids.contains(e.id)),
      trades: removed.any((e) => e.isInvestment),
    )) {
      return false;
    }
    final back = _unskipping(removed, _letGoOf(ids));
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
    if (!_tryCheck([entry])) return false;
    // Back in its own place, as in [restoreAll].
    _entries.restoreAt(entry, _entries.orderOf(entry.id));
    if (!_tryReplay(() => _entries.remove(entry), trades: entry.isInvestment)) {
      return false;
    }
    final back = _unskipping([entry], _letGoOf({entry.id}));
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

  /// Everything that stands in the way of putting [trashed] back as it
  /// is, for the person to decide (D78), all worked out before anything
  /// is asked: for each refund that would come back, [trashed] or one of
  /// its group (review 25), its purchase deleted (each still in the
  /// trash, then gone for good, said once); then the accounts the entries
  /// that would come back name, since closed. Empty when nothing does.
  List<RestoreHold> holdsOf(Trashed trashed) {
    final holds = <RestoreHold>[];
    // Every entry that would come back: each root with its group.
    final entries = {
      trashed.entry.id: trashed.entry,
      for (final t in _withGroup(trashed)) t.entry.id: t.entry,
    };
    var gone = false;
    for (final e in entries.values.toList()) {
      final of = e.refundOf;
      if (of == null || entries.containsKey(of)) continue;
      if (_entries.byId(of) != null) continue;
      final original = _trash.all.where((t) => t.entry.id == of).firstOrNull;
      if (original == null) {
        gone = true;
        continue;
      }
      holds.add(OriginalInTrash(original));
      for (final t in _withGroup(original)) {
        entries[t.entry.id] = t.entry;
      }
    }
    if (gone) holds.add(const OriginalGone());
    final closed = <String, Account>{
      for (final e in entries.values)
        for (final id in {e.account, ?e.to})
          if (_accounts.byId(id) case final a? when a.archived) id: a,
    };
    if (closed.isNotEmpty) holds.add(ClosedAccounts(closed.values.toList()));
    return holds;
  }

  /// Puts [trashed] back in the book as one change, all or nothing. False,
  /// told through [CommandContext.problem] when it no longer fits the
  /// trades kept since, and false with nothing changed when a hold of
  /// [holdsOf] is not agreed: [reopen] opens the closed accounts again,
  /// [withOriginal] puts the refunds' purchases in the trash back first.
  /// A refund whose purchase is gone for good needs no answer here. When
  /// the putting back cannot be done, an account opened for it is closed
  /// again. The screens are told once, when it is done or undone, never
  /// of a state between.
  bool restoreTrashed(
    Trashed trashed, {
    bool reopen = false,
    bool withOriginal = false,
  }) => _told.quietly(
    () => _restoreTrashed(trashed, reopen: reopen, withOriginal: withOriginal),
  );

  bool _restoreTrashed(
    Trashed trashed, {
    required bool reopen,
    required bool withOriginal,
  }) {
    final closed = <Account>[];
    final originals = <Trashed>[];
    for (final hold in holdsOf(trashed)) {
      switch (hold) {
        case ClosedAccounts(:final accounts):
          if (!reopen) return false;
          closed.addAll(accounts);
        case OriginalInTrash(original: final purchase):
          if (!withOriginal) return false;
          originals.add(purchase);
        case OriginalGone():
          break;
      }
    }
    final entry = trashed.entry;
    if (_entries.byId(entry.id) != null) {
      // Already back in the book, as by an undo: only the trash keeps it.
      _trash.removeEntries({entry.id});
      _told.signal();
      _context.keep(WriteBatch(dropped: [(Collection.trash, entry.id)]));
      return true;
    }
    final opened = [for (final a in closed) a.copyWith(archived: false)];
    opened.forEach(_accounts.replace);
    final before = _trash.all;
    final placed = <Trashed>[];
    // The purchases first, then the refunds that name them.
    for (final root in [...originals, trashed]) {
      final back = _withGroup(root);
      if (!_place(back)) {
        _undoPlaced(placed, before, closed);
        return false;
      }
      placed.addAll(back);
    }
    final entries = [for (final t in placed) t.entry];
    final unskipped = _unskipping(entries, {
      for (final t in placed) t.entry.id: ?t.letGo,
    });
    _recurring.replaceExisting(unskipped);
    if (opened.isNotEmpty) _told.changed(const {Topic.accounts});
    _context.keep(
      WriteBatch(
        accounts: opened,
        entries: entries,
        recurring: unskipped,
        dropped: [for (final t in placed) (Collection.trash, t.entry.id)],
      ),
    );
    if (unskipped.isNotEmpty) _told.changed(const {Topic.recurring});
    return true;
  }

  /// [root] with the entries of its group still in the trash, as they
  /// come back from it together: what [holdsOf] weighs is what
  /// [restoreTrashed] puts back.
  List<Trashed> _withGroup(Trashed root) {
    final group = root.entry.group;
    return [
      for (final t in _trash.all)
        if (identical(t, root) ||
            (group != null &&
                t.entry.group == group &&
                _entries.byId(t.entry.id) == null))
          t,
    ];
  }

  /// Puts [back] out of the trash into the entries, each in its own place
  /// (D75), when the write rules and the trades allow; false, told
  /// through [CommandContext.problem], with nothing changed when not.
  bool _place(List<Trashed> back) {
    if (!_tryCheck([for (final t in back) t.entry])) return false;
    final before = _trash.all;
    _trash.removeAll(back);
    for (final t in back) {
      _entries.restoreAt(t.entry, t.order ?? _entries.orderOf(t.entry.id));
    }
    final ids = {for (final t in back) t.entry.id};
    return _tryReplay(() {
      _entries.removeWhere((e) => ids.contains(e.id));
      _trash.replaceWith(before);
    }, trades: back.any((t) => t.entry.isInvestment));
  }

  /// Takes [placed] out of the entries again into the trash as it was
  /// [before], and closes the accounts [closed] again: what [_place] did
  /// for them, undone when a later one is refused.
  void _undoPlaced(
    List<Trashed> placed,
    List<Trashed> before,
    List<Account> closed,
  ) {
    if (placed.isNotEmpty) {
      final ids = {for (final t in placed) t.entry.id};
      _entries.removeWhere((e) => ids.contains(e.id));
      _trash.replaceWith(before);
      if (placed.any((t) => t.entry.isInvestment)) {
        _holdings.replay(_entries.all, today: _context.today);
      }
    }
    closed.forEach(_accounts.replace);
    _told.changed(Topic.all);
  }

  /// Takes out of the trash, for good, the entries deleted longer ago
  /// than it keeps them ([trashRetention]), with their receipt photos, as
  /// opening the book does: also when the day turns with the app open
  /// (D77), so nothing past its time is shown or restored. How many.
  int expireTrash() {
    final from = _context.today.subtract(trashRetention);
    return discardTrashed([
      for (final t in _trash.all)
        if (t.on.isBefore(from)) t,
    ]);
  }

  /// Takes [trashed] out of the trash for good, with their receipt
  /// photos, as one change: such as the deleted entries still naming an
  /// account about to be removed (D78). How many.
  int discardTrashed(Iterable<Trashed> trashed) {
    final gone = [for (final t in trashed) t.entry.id];
    if (gone.isEmpty) return 0;
    _trash.removeEntries({...gone});
    for (final id in gone) {
      _receipts.set(id, null);
    }
    // No sum rests on the trash.
    _told.signal();
    _context.keep(
      WriteBatch(
        receipts: {for (final id in gone) id: null},
        dropped: [for (final id in gone) (Collection.trash, id)],
      ),
    );
    return gone.length;
  }

  /// Puts the spending or income among [entries] under [name]. Splits,
  /// refunds, entries of the other kind and those the ledger would refuse
  /// (kept by an older version, before a rule) keep their own.
  int recategorize(Iterable<Entry> entries, String name) {
    final income = _categories.byName(name).income;
    final changed = [
      for (final e in entries)
        if (_plain(e) &&
            e.parts.isEmpty &&
            e.category != name &&
            (e.type == EntryType.income) == income &&
            _validator.validate(e.withCategory(name), replacing: e) == null)
          e.withCategory(name),
    ];
    replaceAll(changed);
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
      if (!_plain(e) || e.account == id) continue;
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
      if (group.any((g) => _refusals(g.$2, replacing: g.$1) != null)) continue;
      moved.addAll([for (final (_, next) in group) next]);
    }
    replaceAll(moved);
    return moved.length;
  }

  /// [entries] as the book keeps them: a transfer with no category under
  /// [transferCategory], by the one rule the book is read with
  /// ([keptCategory], D80).
  static List<Entry> _kept(List<Entry> entries) => [
    for (final e in entries)
      if (keptCategory(e.type, e.category) case final name
          when name != e.category)
        e.withCategory(name)
      else
        e,
  ];

  /// Spending or income that is not a refund: what a batch may change.
  static bool _plain(Entry e) =>
      (e.type == EntryType.expense || e.type == EntryType.income) &&
      !e.isRefund;

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
    _context.keep(unit.batch);
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

  /// The recurring items [removed] booked, each with the day it lets go:
  /// a booking deleted is a period skipped, not one to book again; and
  /// the day each entry of [removed] stood for, by its id.
  (List<Recurring>, Map<String, DateTime>) _skipping(List<Entry> removed) {
    final changed = <String, Recurring>{};
    final days = <String, DateTime>{};
    for (final e in removed) {
      final day = _recurringService.dueDayOf(e);
      if (day == null) continue;
      // dueDayOf found the item, so it is held.
      final item = changed[e.recurring] ?? _recurring.byId(e.recurring!)!;
      changed[item.id] = item.copyWith(skipped: {...item.skipped, day});
      days[e.id] = day;
    }
    return (changed.values.toList(), days);
  }

  /// The day each trashed entry of [ids] let go when it was deleted.
  Map<String, DateTime> _letGoOf(Set<String> ids) => {
    for (final t in _trash.all)
      if (ids.contains(t.entry.id)) t.entry.id: ?t.letGo,
  };

  /// The recurring items [back] booked with the one day each let go
  /// taken out again: the day it stood for when it was deleted ([letGo],
  /// by entry id), and only if it is still let go. An entry deleted before
  /// that was kept stands for a let-go day of its own month, if any
  /// ([RecurringService.nearestDay]): never another month's.
  List<Recurring> _unskipping(List<Entry> back, Map<String, DateTime> letGo) {
    final changed = <String, Recurring>{};
    for (final e in back) {
      final id = e.recurring;
      if (id == null) continue;
      final item = changed[id] ?? _recurring.byId(id);
      if (item == null) continue;
      final day =
          letGo[e.id] ??
          RecurringService.nearestDay(e.date, [
            for (final d in item.skipped)
              if (d.year == e.date.year && d.month == e.date.month) d,
          ]);
      if (day == null || !item.skipped.contains(day)) continue;
      changed[id] = item.copyWith(skipped: {...item.skipped}..remove(day));
    }
    return changed.values.toList();
  }

  /// Refuses [entries] with a [RecordRefused] when the write rules find
  /// any wrong: each checked in place of the entry of its id that the
  /// ledger holds when [replacing] names it, with the accounts [opening]
  /// brings. Shares are checked by replaying the trades afterwards.
  void _check(
    Iterable<Entry> entries, {
    Iterable<String> replacing = const [],
    Iterable<Account> opening = const [],
  }) {
    final replaced = {...replacing};
    final errors = [
      for (final e in entries)
        ...?_refusals(
          e,
          replacing: replaced.contains(e.id) ? _entries.byId(e.id) : null,
          opening: opening,
        ),
    ];
    if (errors.isNotEmpty) throw RecordRefused(errors);
  }

  /// The errors the write rules find with [e]; null when none.
  List<RecordIssue>? _refusals(
    Entry e, {
    Entry? replacing,
    Iterable<Account> opening = const [],
  }) {
    final errors = [
      for (final issue in _validator.issues(
        e,
        replacing: replacing,
        holdings: false,
        opening: opening,
      ))
        if (issue.isError) issue,
    ];
    return errors.isEmpty ? null : errors;
  }

  /// [_check] for [back], coming back from the trash or an undo, telling a
  /// refusal through [CommandContext.report]; false when refused.
  bool _tryCheck(List<Entry> back) {
    try {
      _check(back);
      return true;
    } on RecordRefused catch (refused) {
      // Said to the person through problem.
      _told.report(refused);
      return false;
    }
  }

  /// Works the holdings out again when [trades] were touched, then tells
  /// the screens the entries changed; an oversold trade is undone and
  /// refused with a [RecordRefused] of [SaleExceedsHolding], as the write
  /// rules refuse it: [SaleExceedsHolding.later] when the trade short is
  /// one the change left as it was.
  void _replayOrUndo(void Function() undo, {bool trades = true}) {
    if (trades) {
      try {
        _holdings.replay(_entries.all, today: _context.today);
      } on OversoldTrade catch (short) {
        undo();
        _holdings.replay(_entries.all, today: _context.today);
        final untouched = identical(_entries.byId(short.entry.id), short.entry);
        throw RecordRefused([SaleExceedsHolding(later: untouched)]);
      }
    }
    _told.changed(const {Topic.entries});
  }

  /// [_replayOrUndo], telling a refusal through [CommandContext.report]
  /// rather than throwing; false when refused.
  bool _tryReplay(void Function() undo, {required bool trades}) {
    try {
      _replayOrUndo(undo, trades: trades);
      return true;
    } on RecordRefused catch (short) {
      // Said to the person through problem.
      _told.report(short);
      _told.changed(Topic.all);
      return false;
    }
  }
}
