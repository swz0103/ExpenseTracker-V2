import 'package:ledger_entries/rules.dart' show RecordIssue, recurringIssues;

import '../cache/topic.dart';
import '../models/models.dart';
import '../persistence/write_batch.dart';
import '../repositories/account_repository.dart';
import '../repositories/recurring_repository.dart';
import '../services/entry_validator.dart';
import '../services/recurring_service.dart';
import 'command_context.dart';
import 'command_exceptions.dart';
import 'entry_commands.dart';
import 'undo.dart';

/// Writes the recurring items and books what falls due.
final class RecurringCommands {
  RecurringCommands({
    required this._context,
    required RecurringRepository recurringRepository,
    required this._accounts,
    required this._recurringService,
    required this._entryCommands,
    required EntryValidator entryValidator,
  }) : _validator = entryValidator,
       _recurring = recurringRepository;

  final CommandContext _context;
  final RecurringRepository _recurring;
  final AccountReader _accounts;
  final RecurringService _recurringService;
  final EntryCommands _entryCommands;
  final EntryValidator _validator;

  /// Takes [day] out of [item]'s skipped days, so it is booked again: 恢復
  /// on the calendar.
  void unskip(Recurring item, DateTime day) {
    if (!item.skipped.contains(day)) return;
    final from = item.openFrom;
    saveRecurring(
      item.copyWith(
        skipped: {...item.skipped}..remove(day),
        // Asked for again, even with no booking left from before it.
        openFrom: from == null || day.isBefore(from) ? day : from,
      ),
    );
  }

  /// Why booking [item] on [day] (its pending day unless given) would be
  /// refused, as [confirm] would throw it; null when it would not.
  RecordIssue? refusalOf(Recurring item, {DateTime? day}) =>
      _validator.validate(_recurringService.booking(item, day: day));

  /// Books [item] on [day] (D66: the day pressed on the calendar), else on
  /// its pending day; a booking the ledger refuses, such as one in
  /// another currency with no rate for its day, throws a [RecordRefused].
  void confirm(Recurring item, {DateTime? day}) {
    _entryCommands.add(
      _recurringService.booking(item, day: day).withId(_context.newId()),
    );
  }

  /// Most days of one item [bookDays] books in one go: what a daily item
  /// left for months would otherwise write at once. The rest stay due,
  /// and are listed again.
  static const bookedAtOnce = 62;

  /// Books the day of each item marked [Recurring.auto] that has come and
  /// is not booked yet, on its own day, all in one change, when it is
  /// that item's only one: run when the ledger opens and when the day
  /// turns, so no background work is needed. An item with more than one
  /// day waiting, after a restore or a long absence, is not booked but
  /// listed ([AutoBooking.held]) for the person to confirm first (D61),
  /// through [bookDays]; and a day it cannot book by itself, such as one
  /// in another currency with no rate for that day (R5) or into an
  /// account since closed, waits, listed with why.
  AutoBooking bookDue() {
    final booked = <Entry>[];
    final held = <HeldBooking>[];
    for (final item in _recurring.all) {
      if (!item.auto || !item.active) continue;
      final days = _recurringService.unpostedDates(
        item,
        from: DateTime.utc(1),
        to: _context.today,
      );
      if (days.isEmpty) continue;
      final day = days.first;
      final closed = _closed(item);
      final refusal = closed ? null : refusalOf(item, day: day);
      if (days.length > 1 || closed || refusal != null) {
        held.add(HeldBooking(item, days, refusal: refusal, closed: closed));
        continue;
      }
      booked.add(
        _recurringService.booking(item, day: day).withId(_context.newId()),
      );
    }
    if (booked.isNotEmpty) _entryCommands.addAll(booked);
    return AutoBooking(booked.length, held);
  }

  /// Whether [item]'s account is closed (archived): nothing is booked
  /// into it by itself.
  bool _closed(Recurring item) =>
      _accounts.byId(item.account)?.archived ?? false;

  /// Books [days] of [item] as the person confirmed them, each on its own
  /// day, all in one change: at most [bookedAtOnce], the earliest first.
  /// Days the ledger would refuse (another currency with no rate for the
  /// day) are left, for the person to book by hand; how many were booked.
  int bookDays(Recurring item, List<DateTime> days) {
    final booked = <Entry>[
      for (final day in days.take(bookedAtOnce))
        if (refusalOf(item, day: day) == null)
          _recurringService.booking(item, day: day).withId(_context.newId()),
    ];
    if (booked.isNotEmpty) _entryCommands.addAll(booked);
    return booked.length;
  }

  /// Puts [item] in place of the one with the same id, or adds it; one
  /// the ledger's write rules refuse throws a [RecordRefused].
  void saveRecurring(Recurring item) {
    // A day let go that the item, as changed, no longer falls on is
    // forgotten (R4, F82): it would hide a day it falls on later.
    final kept = {
      for (final d in item.skipped)
        if (item.fallsOn(d)) d,
    };
    if (kept.length != item.skipped.length) {
      item = item.copyWith(skipped: kept);
    }
    final issues = recurringIssues(
      amount: item.amount,
      every: item.every,
      day: item.day,
      start: item.start,
      end: item.end,
    );
    if (issues.isNotEmpty) throw RecordRefused(issues);
    _recurring.put(item);
    _context.changed(const {Topic.recurring});
    _context.keep(WriteBatch(recurring: [item]));
  }

  /// Takes away the item [id]; what it booked stays. The [Undo] puts it
  /// back where it stood (D82). Null when there is none.
  Undo? removeRecurring(String id) {
    final found = _recurring.remove(id);
    if (found == null) return null;
    final (index, removed) = found;
    _context.changed(const {Topic.recurring});
    _context.keep(WriteBatch(dropped: [(Collection.recurring, removed.id)]));
    return () {
      _recurring.putAt(index, removed);
      _context.changed(const {Topic.recurring});
      _context.keep(WriteBatch(recurring: [removed]));
    };
  }
}

/// What [RecurringCommands.bookDue] did: how many days it booked, and the
/// items it left for the person to confirm.
final class AutoBooking {
  const AutoBooking(this.booked, this.held);

  /// Nothing booked, nothing left.
  static const none = AutoBooking(0, []);

  final int booked;
  final List<HeldBooking> held;
}

/// An item marked to book itself that [RecurringCommands.bookDue] left:
/// more than one day waiting ([days], the earliest first, D61), or one it
/// cannot book by itself: its account [closed], or what the ledger would
/// refuse ([refusal], such as no rate for a foreign day, R5).
final class HeldBooking {
  const HeldBooking(this.item, this.days, {this.refusal, this.closed = false});

  final Recurring item;
  final List<DateTime> days;
  final RecordIssue? refusal;
  final bool closed;

  /// Whether it is left only to be confirmed: the person may book it as
  /// it is.
  bool get confirmable => refusal == null && !closed;
}
