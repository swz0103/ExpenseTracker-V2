import 'package:ledger_entries/rules.dart' show RecordIssue, SaleExceedsHolding;

import '../cache/topic.dart';
import '../models/models.dart';
import '../portfolio.dart' show OversoldTrade;
import '../repositories/entry_repository.dart';
import '../repositories/holding_repository.dart';
import '../repositories/recurring_repository.dart';
import '../repositories/trash_repository.dart';
import '../services/entry_validator.dart';
import '../services/recurring_service.dart';
import 'command_context.dart';
import 'command_exceptions.dart';
import 'held_notices.dart';

/// The bookkeeping every write of the entries shares (`EntryCommands`,
/// `TrashCommands`, `EntryBulkEdits`): what the write rules refuse, the
/// trades worked out again and a refusal undone exactly, and the
/// recurring days a deletion lets go and a putting back takes again.
final class EntryBookkeeping {
  EntryBookkeeping({
    required this._context,
    required this._told,
    required this._entries,
    required this._holdings,
    required this._recurring,
    required this._trash,
    required this._recurringService,
    required this._validator,
  });

  final CommandContext _context;
  final HeldNotices _told;
  final EntryRepository _entries;
  final HoldingRepository _holdings;
  final RecurringRepository _recurring;
  final TrashRepository _trash;
  final RecurringService _recurringService;
  final EntryValidator _validator;

  /// [entries] as the book keeps them: a transfer with no category under
  /// [transferCategory], by the one rule the book is read with
  /// ([keptCategory], D80).
  static List<Entry> kept(List<Entry> entries) => [
    for (final e in entries)
      if (keptCategory(e.type, e.category) case final name
          when name != e.category)
        e.withCategory(name)
      else
        e,
  ];

  /// Spending or income that is not a refund: what a batch may change.
  static bool plain(Entry e) =>
      (e.type == EntryType.expense || e.type == EntryType.income) &&
      !e.isRefund;

  /// The recurring items [removed] booked, each with the day it lets go:
  /// a booking deleted is a period skipped, not one to book again; and
  /// the day each entry of [removed] stood for, by its id.
  (List<Recurring>, Map<String, DateTime>) skipping(List<Entry> removed) {
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
  Map<String, DateTime> letGoOf(Set<String> ids) => {
    for (final t in _trash.all)
      if (ids.contains(t.entry.id)) t.entry.id: ?t.letGo,
  };

  /// The recurring items [back] booked with the one day each let go
  /// taken out again: the day it stood for when it was deleted ([letGo],
  /// by entry id), and only if it is still let go. An entry deleted before
  /// that was kept stands for a let-go day of its own month, if any
  /// ([RecurringService.nearestDay]): never another month's.
  List<Recurring> unskipping(List<Entry> back, Map<String, DateTime> letGo) {
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
  /// brings, [settling] the account they settle before it is archived
  /// (`EntryCommands.addSettlement`), [back] when they come back from the trash or an
  /// undo on the days the book held them on. Shares are checked by
  /// replaying the trades afterwards.
  void check(
    Iterable<Entry> entries, {
    Iterable<String> replacing = const [],
    Iterable<Account> opening = const [],
    String? settling,
    bool back = false,
  }) {
    final replaced = {...replacing};
    final errors = [
      for (final e in entries)
        ...?refusals(
          e,
          replacing: replaced.contains(e.id) ? _entries.byId(e.id) : null,
          opening: opening,
          settling: settling,
          back: back,
        ),
    ];
    if (errors.isNotEmpty) throw RecordRefused(errors);
  }

  /// The errors the write rules find with [e]; null when none.
  List<RecordIssue>? refusals(
    Entry e, {
    Entry? replacing,
    Iterable<Account> opening = const [],
    String? settling,
    bool back = false,
  }) {
    final errors = [
      for (final issue in _validator.issues(
        e,
        replacing: replacing,
        holdings: false,
        opening: opening,
        settling: settling,
        back: back,
      ))
        if (issue.isError) issue,
    ];
    return errors.isEmpty ? null : errors;
  }

  /// [check] for [back], coming back from the trash or an undo, telling a
  /// refusal through [CommandContext.report]; false when refused.
  bool tryCheck(List<Entry> back) {
    try {
      check(back, back: true);
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
  void replayOrUndo(void Function() undo, {bool trades = true}) {
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

  /// [replayOrUndo], telling a refusal through [CommandContext.report]
  /// rather than throwing; false when refused.
  bool tryReplay(void Function() undo, {required bool trades}) {
    try {
      replayOrUndo(undo, trades: trades);
      return true;
    } on RecordRefused catch (short) {
      // Said to the person through problem.
      _told.report(short);
      _told.changed(Topic.all);
      return false;
    }
  }
}
