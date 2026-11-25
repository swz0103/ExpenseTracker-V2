import 'package:core/constants/retention.dart';

import '../cache/topic.dart';
import '../models/models.dart';
import '../persistence/write_batch.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/holding_repository.dart';
import '../repositories/receipt_repository.dart';
import '../repositories/recurring_repository.dart';
import '../repositories/trash_repository.dart';
import 'command_context.dart';
import 'entry_bookkeeping.dart';
import 'held_notices.dart';
import 'restore_hold.dart';

/// The trash's own changes: putting a deleted entry back from it, with
/// what stands in the way (D78), and taking entries out of it for good.
/// Reached through `EntryCommands`, which shares its bookkeeping.
final class TrashCommands {
  TrashCommands({
    required this._context,
    required this._told,
    required this._book,
    required this._entries,
    required this._accounts,
    required this._holdings,
    required this._recurring,
    required this._trash,
    required this._receipts,
  });

  final CommandContext _context;
  final HeldNotices _told;
  final EntryBookkeeping _book;
  final EntryRepository _entries;
  final AccountRepository _accounts;
  final HoldingRepository _holdings;
  final RecurringRepository _recurring;
  final TrashRepository _trash;
  final ReceiptRepository _receipts;

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
    final unskipped = _book.unskipping(entries, {
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
    if (!_book.tryCheck([for (final t in back) t.entry])) return false;
    final before = _trash.all;
    _trash.removeAll(back);
    for (final t in back) {
      _entries.restoreAt(t.entry, t.order ?? _entries.orderOf(t.entry.id));
    }
    final ids = {for (final t in back) t.entry.id};
    return _book.tryReplay(() {
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
}
