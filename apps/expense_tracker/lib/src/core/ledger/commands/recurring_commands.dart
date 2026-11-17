import '../cache/topic.dart';
import '../models/models.dart';
import '../persistence/ledger_data_source.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/recurring_repository.dart';
import '../services/recurring_service.dart';
import 'command_context.dart';
import 'entry_commands.dart';

/// Writes the recurring items and books what falls due.
final class RecurringCommands {
  RecurringCommands({
    required this._context,
    required RecurringRepository recurringRepository,
    required EntryRepository entryRepository,
    required this._accounts,
    required this._recurringService,
    required this._entryCommands,
  }) : _recurring = recurringRepository,
       _entries = entryRepository;

  final CommandContext _context;
  final RecurringRepository _recurring;
  final EntryRepository _entries;
  final AccountReader _accounts;
  final RecurringService _recurringService;
  final EntryCommands _entryCommands;

  /// Takes [day] out of [item]'s skipped days, so it is booked again: 恢復
  /// on the calendar.
  void unskip(Recurring item, DateTime day) {
    if (!item.skipped.contains(day)) return;
    saveRecurring(item.copyWith(skipped: {...item.skipped}..remove(day)));
  }

  /// Books [item] as it stands.
  void confirm(Recurring item) {
    _entryCommands.add(
      _recurringService.booking(item).withId(_context.newId()),
    );
  }

  /// Books every day of the items marked [Recurring.auto] that has come
  /// and is not booked yet, on its own day, all in one change; returns
  /// how many were booked. Run when the ledger opens and when the day
  /// turns, so no background work is needed.
  int bookDue() {
    final booked = <Entry>[];
    for (final item in _recurring.all) {
      if (!item.auto || !item.active) continue;
      // Each booking settles one day; a missed one from last month comes
      // first. Bounded, in case an item's dates do not move on.
      final days = <DateTime>{};
      for (var i = 0; i < 62; i++) {
        final day = _recurringService.pendingDate(item);
        if (day == null || day.isAfter(_context.today) || !days.add(day)) break;
        if (item.amount <= 0 ||
            !_accounts.contains(item.account) ||
            _accounts.resolve(item.account).archived) {
          break;
        }
        final entry = _recurringService.booking(item).withId(_context.newId());
        // Kept in the list so the next pending day counts it.
        _entries.add(entry);
        _context.forget(const {Topic.entries});
        booked.add(entry);
      }
    }
    if (booked.isEmpty) return 0;
    _entries.removeRange(_entries.length - booked.length, _entries.length);
    _entryCommands.addAll(booked);
    return booked.length;
  }

  /// Puts [item] in place of the one with the same id, or adds it.
  void saveRecurring(Recurring item) {
    _recurring.put(item);
    _context.changed(const {Topic.recurring});
    _context.keep(WriteBatch(recurring: [item]));
  }

  void removeRecurring(String id) {
    final removed = _recurring.remove(id);
    if (removed == null) return;
    _context.changed(const {Topic.recurring});
    _context.keep(WriteBatch(dropped: [(Collection.recurring, removed.id)]));
  }
}
