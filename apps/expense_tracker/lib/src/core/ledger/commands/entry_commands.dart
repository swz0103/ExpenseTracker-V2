import '../cache/topic.dart';
import '../models/models.dart';
import '../persistence/ledger_data_source.dart';
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

/// Writes the entries: adding, changing, removing and bringing them back,
/// one at a time, as a group or many at once; each change is kept as one
/// batch. A change that would sell shares not held is refused.
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

  /// Adds [entry], with its receipt photo [receipt] when one is given; a
  /// sale of more shares than are held is refused with a [StateError].
  void add(Entry entry, {String? receipt}) {
    _entries.add(entry);
    _replayOrUndo(() => _entries.removeLast(), trades: entry.isInvestment);
    if (receipt != null) _receipts.set(entry.id, receipt);
    _context.keep(WriteBatch(entries: [entry], receipts: {entry.id: ?receipt}));
  }

  /// Adds every one of [entries] at once, with the [accounts] and
  /// [categories] they bring, as an import does: all of it is kept
  /// together, or none.
  void addAll(
    List<Entry> entries, {
    List<Account> accounts = const [],
    List<Category> categories = const [],
  }) {
    if (entries.isEmpty && accounts.isEmpty && categories.isEmpty) return;
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
    _context.changed(Topic.all);
    _context.keep(
      WriteBatch(accounts: opened, categories: named, entries: entries),
    );
  }

  /// Puts [entry] in place of the entry with the same id, with the receipt
  /// photo [receipt] (null takes it away).
  void replace(Entry entry, {String? receipt}) {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index < 0) return add(entry, receipt: receipt);
    final before = _entries[index];
    _entries[index] = entry;
    _replayOrUndo(
      () => _entries[index] = before,
      trades: entry.isInvestment || before.isInvestment,
    );
    final photo = _receipts.set(entry.id, receipt);
    _context.keep(
      WriteBatch(entries: [entry], receipts: {if (photo) entry.id: receipt}),
    );
  }

  /// Puts each of [entries] in place of the one with the same id, as one
  /// change; those the ledger does not hold are left out.
  void replaceAll(List<Entry> entries) {
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

  /// Puts [entries], written as one, in place of the entries [was] held:
  /// those kept are changed, new ones added and the rest taken away (not
  /// to the trash: they are part of the same change), with the receipt
  /// photo [receipt] on [receiptOn].
  void replaceGroup(
    List<Entry> entries,
    Iterable<String> was, {
    String? receipt,
    String? receiptOn,
  }) {
    final before = List.of(_entries);
    final ids = {for (final e in entries) e.id};
    final gone = {...was}..removeAll(ids);
    _entries.removeWhere((e) => gone.contains(e.id));
    for (final e in entries) {
      final index = _entries.indexWhere((x) => x.id == e.id);
      if (index < 0) {
        _entries.add(e);
      } else {
        _entries[index] = e;
      }
    }
    _replayOrUndo(
      () => _entries
        ..clear()
        ..addAll(before),
      trades: entries.any((e) => e.isInvestment),
    );
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

  /// Removes the entry with [id] and returns it with its place, for undo.
  /// Null when there is none, or when taking it away would leave a later
  /// sale short of shares: that is told through [problem].
  (int, Entry)? remove(String id) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return null;
    // Its period, worked out while it still counts.
    final skipping = _skipping([_entries[index]]);
    final removed = _entries.removeAt(index);
    if (!_tryReplay(
      () => _entries.insert(index, removed),
      trades: removed.isInvestment,
    )) {
      return null;
    }
    _recurring.replaceExisting(skipping);
    final trashed = Trashed(removed, _context.today);
    _trash.put(trashed);
    _context.keep(
      WriteBatch(
        trash: [trashed],
        recurring: skipping,
        dropped: [(Collection.entry, removed.id)],
      ),
    );
    if (skipping.isNotEmpty) _context.changed(const {Topic.recurring});
    return (index, removed);
  }

  /// Removes every entry of [ids] as one change, and returns each with its
  /// place, for undo; none when taking them away would leave a later sale
  /// short of shares, which is told through [problem].
  List<(int, Entry)> removeAll(Iterable<String> ids) {
    final wanted = {...ids};
    final removed = <(int, Entry)>[
      for (final (i, e) in _entries.indexed)
        if (wanted.contains(e.id)) (i, e),
    ];
    if (removed.isEmpty) return const [];
    final skipping = _skipping([for (final (_, e) in removed) e]);
    _entries.removeWhere((e) => wanted.contains(e.id));
    if (!_tryReplay(() {
      for (final (i, e) in removed) {
        _entries.insert(i, e);
      }
    }, trades: removed.any((r) => r.$2.isInvestment))) {
      return const [];
    }
    _recurring.replaceExisting(skipping);
    final trashed = [for (final (_, e) in removed) Trashed(e, _context.today)];
    _trash.putAll(trashed);
    _context.keep(
      WriteBatch(
        trash: trashed,
        recurring: skipping,
        dropped: [for (final (_, e) in removed) (Collection.entry, e.id)],
      ),
    );
    if (skipping.isNotEmpty) _context.changed(const {Topic.recurring});
    return removed;
  }

  /// Puts back what [removeAll] took away, as one change.
  bool restoreAll(List<(int, Entry)> removed) {
    if (removed.isEmpty) return true;
    final ids = {for (final (_, e) in removed) e.id};
    if (_entries.any((e) => ids.contains(e.id))) return false;
    for (final (i, e) in removed) {
      _entries.insert(i.clamp(0, _entries.length), e);
    }
    if (!_tryReplay(
      () => _entries.removeWhere((e) => ids.contains(e.id)),
      trades: removed.any((r) => r.$2.isInvestment),
    )) {
      return false;
    }
    _trash.removeEntries(ids);
    final back = _unskipping([for (final (_, e) in removed) e]);
    _recurring.replaceExisting(back);
    _context.keep(
      WriteBatch(
        entries: [for (final (_, e) in removed) e],
        recurring: back,
        dropped: [for (final id in ids) (Collection.trash, id)],
      ),
    );
    if (back.isNotEmpty) _context.changed(const {Topic.recurring});
    return true;
  }

  /// Puts back an entry [remove] took away. False, told through
  /// [problem], when it no longer fits the trades kept since.
  bool restore((int, Entry) removed) {
    final (index, entry) = removed;
    if (_entries.byId(entry.id) != null) return false;
    _entries.insert(index.clamp(0, _entries.length), entry);
    if (!_tryReplay(() => _entries.remove(entry), trades: entry.isInvestment)) {
      return false;
    }
    _trash.removeEntries({entry.id});
    final back = _unskipping([entry]);
    _recurring.replaceExisting(back);
    _context.keep(
      WriteBatch(
        entries: [entry],
        recurring: back,
        dropped: [(Collection.trash, entry.id)],
      ),
    );
    if (back.isNotEmpty) _context.changed(const {Topic.recurring});
    return true;
  }

  /// Puts [trashed] back in the book. False, told through [problem], when
  /// it no longer fits the trades kept since.
  bool restoreTrashed(Trashed trashed) {
    final entry = trashed.entry;
    if (_entries.byId(entry.id) != null) {
      // Already back in the book, as by an undo: only the trash keeps it.
      _trash.removeEntries({entry.id});
      _context.signal();
      _context.keep(WriteBatch(dropped: [(Collection.trash, entry.id)]));
      return true;
    }
    // An entry written as one with others comes back with them.
    final group = entry.group;
    final back = [
      for (final t in _trash.all)
        if (identical(t, trashed) ||
            (group != null &&
                t.entry.group == group &&
                _entries.byId(t.entry.id) == null))
          t,
    ];
    final before = _trash.all;
    _trash.removeAll(back);
    final count = _entries.length;
    _entries.addAll([for (final t in back) t.entry]);
    if (!_tryReplay(() {
      _entries.removeRange(count, _entries.length);
      _trash.replaceWith(before);
    }, trades: back.any((t) => t.entry.isInvestment))) {
      return false;
    }
    final unskipped = _unskipping([for (final t in back) t.entry]);
    _recurring.replaceExisting(unskipped);
    _context.keep(
      WriteBatch(
        entries: [for (final t in back) t.entry],
        recurring: unskipped,
        dropped: [for (final t in back) (Collection.trash, t.entry.id)],
      ),
    );
    if (unskipped.isNotEmpty) _context.changed(const {Topic.recurring});
    return true;
  }

  /// Puts the spending or income among [entries] under [name]. Splits,
  /// refunds and entries of the other kind keep their own.
  int recategorize(Iterable<Entry> entries, String name) {
    final income = _categories.byName(name).income;
    final changed = [
      for (final e in entries)
        if (_plain(e) &&
            e.parts.isEmpty &&
            e.category != name &&
            (e.type == EntryType.income) == income)
          e.withCategory(name),
    ];
    replaceAll(changed);
    return changed.length;
  }

  /// Moves the spending and income among [entries] to [id], an account in
  /// the same currency. Refunded spending, instalment purchases off a card
  /// and entries the ledger would refuse stay where they are.
  int moveToAccount(Iterable<Entry> entries, String id) {
    final into = _accounts.resolve(id);
    final moved = <Entry>[];
    for (final e in [...entries]) {
      if (!_plain(e) || e.account == id) continue;
      if (_accounts.resolve(e.account).currency != into.currency) continue;
      if (e.installments > 1 && into.kind != AccountKind.card) continue;
      if (e.type == EntryType.expense &&
          _entryQueries.refundable(e) != e.amount) {
        continue;
      }
      final next = e.withAccount(id);
      if (_validator.problemWith(next, replacing: e) != null) continue;
      moved.add(next);
      // What was paid in it for others went from the same account.
      for (final m in _entryQueries.groupOf(e)) {
        if (m.type == EntryType.transfer && m.account == e.account) {
          moved.add(m.withAccount(id));
        }
      }
    }
    replaceAll(moved);
    return moved.length;
  }

  /// Spending or income that is not a refund: what a batch may change.
  static bool _plain(Entry e) =>
      (e.type == EntryType.expense || e.type == EntryType.income) &&
      !e.isRefund;

  /// Renames or merges a tag across every entry; an empty [to] removes it.
  void renameTag(String from, String to) {
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
    unit.registerAllDirty(_entries.changeAll(retagged));
    unit.registerAllDirty(_trash.changeEntries(retagged));
    _context.changed(Topic.all);
    _context.keep(unit.batch);
  }

  /// Renames or merges a merchant across every entry; an empty [to]
  /// clears it.
  void renameMerchant(String from, String to) {
    final unit = UnitOfWork();
    Entry? renamed(Entry e) =>
        e.merchant == from ? e.withLabels(merchant: to) : null;
    unit.registerAllDirty(_entries.changeAll(renamed));
    unit.registerAllDirty(_trash.changeEntries(renamed));
    _context.changed(Topic.all);
    _context.keep(unit.batch);
  }

  /// The recurring items [removed] booked, each with the day it lets go:
  /// a booking deleted is a period skipped, not one to book again.
  List<Recurring> _skipping(List<Entry> removed) {
    final changed = <String, Recurring>{};
    for (final e in removed) {
      final day = _recurringService.dueDayOf(e);
      if (day == null) continue;
      // dueDayOf found the item, so it is held.
      final item = changed[e.recurring] ?? _recurring.byId(e.recurring!)!;
      changed[item.id] = item.copyWith(skipped: {...item.skipped, day});
    }
    return changed.values.toList();
  }

  /// The recurring items [back] booked with the day each had let go
  /// taken out again: the one nearest the entry in its month.
  List<Recurring> _unskipping(List<Entry> back) {
    final changed = <String, Recurring>{};
    for (final e in back) {
      final id = e.recurring;
      if (id == null) continue;
      final item = changed[id] ?? _recurring.byId(id);
      if (item == null) continue;
      final days =
          [
            for (final d in item.skipped)
              if (d.year == e.date.year && d.month == e.date.month) d,
          ]..sort(
            (a, b) => (a.difference(e.date).abs()).compareTo(
              b.difference(e.date).abs(),
            ),
          );
      if (days.isEmpty) continue;
      changed[id] = item.copyWith(
        skipped: {...item.skipped}..remove(days.first),
      );
    }
    return changed.values.toList();
  }

  /// Works the holdings out again when [trades] were touched, then tells
  /// the screens the entries changed; an oversold trade is undone and
  /// rethrown.
  void _replayOrUndo(void Function() undo, {bool trades = true}) {
    if (trades) {
      try {
        _holdings.replay(_entries);
      } on StateError {
        undo();
        _holdings.replay(_entries);
        rethrow;
      }
    }
    _context.changed(const {Topic.entries});
  }

  /// [_replayOrUndo], telling a refusal through [problem] rather than
  /// throwing; false when refused.
  bool _tryReplay(void Function() undo, {required bool trades}) {
    try {
      _replayOrUndo(undo, trades: trades);
      return true;
    } on StateError {
      // Said to the person through problem.
      _context.problem.value = const SharesShort();
      _context.changed(Topic.all);
      return false;
    }
  }
}
