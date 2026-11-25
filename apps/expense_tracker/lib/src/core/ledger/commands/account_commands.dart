import 'package:core/foundation_values.dart';
import 'package:domain/credit_cards.dart';
import 'package:ledger_entries/rules.dart'
    show CloseMoveRefused, RecordIssue, accountIssues;

import '../cache/topic.dart';
import '../card_cycle.dart';
import '../models/models.dart';
import '../persistence/write_batch.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/recurring_repository.dart';
import '../repositories/trash_repository.dart';
import '../services/balance_service.dart';
import 'command_context.dart';
import 'command_exceptions.dart';
import 'undo.dart';

import 'dart:math';

/// Writes the accounts: adding, changing, ordering and removing them, a
/// balance set by hand and a card's statement close moved. An account or
/// a moved close the ledger's write rules refuse throws a [RecordRefused]
/// before anything changes.
final class AccountCommands {
  AccountCommands({
    required this._context,
    required AccountRepository accountRepository,
    required EntryRepository entryRepository,
    required TrashRepository trashRepository,
    required RecurringRepository recurringRepository,
    required BalanceService balanceService,
  }) : _accounts = accountRepository,
       _entries = entryRepository,
       _trash = trashRepository,
       _recurring = recurringRepository,
       _balances = balanceService;

  final CommandContext _context;
  final AccountRepository _accounts;
  final EntryRepository _entries;
  final TrashRepository _trash;
  final RecurringRepository _recurring;
  final BalanceService _balances;

  void addAccount(Account account) {
    _check(account);
    _accounts.add(account);
    _context.changed(const {Topic.accounts});
    _context.keep(WriteBatch(accounts: [account]));
  }

  /// Puts [account] in place of the one with the same id.
  void updateAccount(Account account) {
    final before = _accounts.byId(account.id);
    if (before == null) return addAccount(account);
    _check(account);
    // A form that does not show a card's moved closes and earlier billing
    // days keeps them.
    account = account.copyWith(
      closes: account.closes.isEmpty ? before.closes : null,
      history: account.history.isEmpty ? before.history : null,
    );
    account = _rescheduled(before, account);
    _accounts.replace(account);
    _context.changed(const {Topic.accounts});
    _context.keep(WriteBatch(accounts: [account]));
  }

  /// [after] keeping [before]'s billing days for the statements closing
  /// before the next close on the new day, as the ledger keeps them.
  Account _rescheduled(Account before, Account after) {
    final closing = before.closingDay;
    final due = before.dueDay;
    if (after.kind != AccountKind.card ||
        closing == null ||
        due == null ||
        ((after.closingDay ?? closing) == closing &&
            (after.dueDay ?? due) == due)) {
      return after;
    }
    final day = after.closingDay ?? closing;
    var from = monthEnd(_context.today.year, _context.today.month);
    for (final month in [_context.today.month, _context.today.month + 1]) {
      final last = monthEnd(_context.today.year, month);
      final close = DateTime.utc(last.year, last.month, min(day, last.day));
      if (close.isAfter(_context.today)) {
        from = close;
        break;
      }
    }
    final until = BusinessDate(from.year, from.month, from.day);
    final kept = before.history;
    // Days changed again before the last change took effect: the days
    // before that one still hold until the first close on the newest.
    final pending =
        kept.isNotEmpty &&
        kept.last.until.compareTo(
              BusinessDate(
                _context.today.year,
                _context.today.month,
                _context.today.day,
              ),
            ) >
            0;
    return after.copyWith(
      history: [
        ...(pending ? kept.sublist(0, kept.length - 1) : kept),
        CardScheduleChange(
          until: until,
          closingDay: pending ? kept.last.closingDay : closing,
          dueDay: pending ? kept.last.dueDay : due,
        ),
      ],
    );
  }

  /// Puts the accounts of [ids] in that order on 我的帳戶; the others
  /// keep their places.
  void placeAccounts(List<String> ids) {
    final moved = _accounts.place(ids);
    if (moved.isEmpty) return;
    _context.changed(const {Topic.accounts});
    _context.keep(WriteBatch(accounts: moved));
  }

  /// Corrects [id]'s balance today to [target] by moving its opening
  /// balance, so its history keeps its shape.
  void setBalance(String id, int target) {
    final a = _accounts.byId(id);
    if (a == null) return;
    final moved = a.copyWith(
      opening: a.opening + target - _balances.balance(id),
    );
    _accounts.replace(moved);
    _context.changed(const {Topic.accounts});
    _context.keep(WriteBatch(accounts: [moved]));
  }

  /// Moves the close of [cardId]'s statement scheduled on [scheduled] to
  /// [closesOn], up to a week either way, as a bank does around a holiday.
  void moveClose(String cardId, DateTime scheduled, DateTime closesOn) {
    final card = _accounts.byId(cardId);
    if (card == null) return;
    if (!card.canMoveClose(scheduled, closesOn)) {
      throw RecordRefused(const [CloseMoveRefused()]);
    }
    final moved = card.copyWith(closes: {...card.closes, scheduled: closesOn});
    _accounts.replace(moved);
    _context.changed(Topic.all);
    _context.keep(WriteBatch(accounts: [moved]));
  }

  /// Refuses [account] with a [RecordRefused] when the write rules find
  /// it wrong.
  static void _check(Account account) {
    final List<RecordIssue> issues = accountIssues(
      name: account.name,
      closingDay: account.closingDay,
      dueDay: account.dueDay,
      limit: account.limit,
      loanRate: account.loan?.rate,
    );
    if (issues.isNotEmpty) throw RecordRefused(issues);
  }

  /// Whether anything still names account [id]: an entry, one in the
  /// trash that may come back, or a recurring item. One in use is
  /// archived rather than deleted, so nothing is left pointing nowhere.
  bool isUsed(String id) =>
      _entries.any((e) => e.account == id || e.to == id) ||
      _trash.mentionsAccount(id) ||
      _recurring.mentionsAccount(id);

  /// Whether an entry in the book or a recurring item names [id]: what
  /// keeps it from being removed, whatever the trash holds.
  bool usedOutsideTrash(String id) =>
      _entries.any((e) => e.account == id || e.to == id) ||
      _recurring.mentionsAccount(id);

  /// The deleted entries, still in the trash, that name [id]: they keep
  /// it from being removed until they are emptied (D78).
  List<Trashed> trashedNaming(String id) => _trash.mentioning(id);

  /// Takes away the account [id] when nothing names it ([isUsed]); the
  /// [Undo] puts it back where it stood (D82). Null when it is not taken.
  Undo? removeAccount(String id) {
    if (isUsed(id)) return null;
    final found = _accounts.removeAt(id);
    if (found == null) return null;
    final (index, removed) = found;
    _context.changed(Topic.all);
    _context.keep(WriteBatch(dropped: [(Collection.account, removed.id)]));
    return () {
      if (!_accounts.putAt(index, removed)) return;
      _context.changed(Topic.all);
      _context.keep(WriteBatch(accounts: [removed], putBack: true));
    };
  }

  /// Archives the account [id], or brings it back when [archived] is
  /// false; the [Undo] sets it as it was (D82). Null when there is none
  /// or it already is so.
  Undo? setArchived(String id, {required bool archived}) {
    final before = _accounts.byId(id);
    if (before == null || before.archived == archived) return null;
    updateAccount(before.copyWith(archived: archived));
    return () {
      final now = _accounts.byId(id);
      if (now == null || now.archived != archived) return;
      updateAccount(now.copyWith(archived: !archived));
    };
  }
}
