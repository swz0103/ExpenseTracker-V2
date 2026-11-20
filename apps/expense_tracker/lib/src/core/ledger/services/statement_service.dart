import '../cache/query_cache.dart';
import 'tracked_readers.dart';
import '../card_cycle.dart';
import '../cache/topic.dart';
import '../models/models.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';
import 'balance_service.dart';

import 'dart:math';

/// Card statements: what has been billed, what is due and what is not
/// billed yet. A statement closes at the end of its day.
final class StatementService {
  StatementService({
    required EntryReader entries,
    required AccountReader accounts,
    required BalanceService balanceService,
    required this._cache,
    required this._today,
  }) : _balances = balanceService,
       _entries = TrackedEntryReader(entries, _cache),
       _accounts = TrackedAccountReader(accounts, _cache);

  final EntryReader _entries;
  final AccountReader _accounts;
  final BalanceService _balances;
  final QueryCache _cache;
  final DateTime Function() _today;

  /// The card comes in as an argument: its own changes are not read, so
  /// every answer about a card rests on the accounts as well.
  static const _cardTopics = {Topic.accounts};

  /// How much of [e] has reached its card's statements by [at]: all of
  /// it, or the instalments billed so far.
  int billed(Entry e, DateTime at) =>
      _accounts.resolve(e.account).billed(e, at);

  /// How many instalments of [e] have been billed by [at].
  int billedPeriods(Entry e, DateTime at) =>
      _accounts.resolve(e.account).billedPeriods(e, at);

  /// The last day whose statement closes are behind: a statement closes
  /// at the end of its day, so one closing today is still open.
  DateTime get closedBy => _today().subtract(const Duration(days: 1));

  /// The last closed statement of [card]: its first and last day and when
  /// it must be paid.
  (DateTime, DateTime, DateTime) statement(Account card) =>
      _cache.remember(('statement', card.id, closedBy), () {
        final end = card.closingOn(closedBy);
        final (start, due) = card.cycleEnding(end);
        return (start, end, due);
      }, reads: _cardTopics);

  /// What is still to pay on the last statement of [card]: what it owed
  /// when the statement closed, less what was paid in since.
  int statementDue(Account card) => _cache.remember(
    ('due', card.id, closedBy),
    () => _statementDue(card),
    reads: _cardTopics,
  );

  int _statementDue(Account card) {
    final (_, end, _) = statement(card);
    var paid = 0;
    for (final e in _entries.all) {
      if (e.type == EntryType.transfer &&
          e.to == card.id &&
          e.date.isAfter(end)) {
        paid += e.arrived;
      }
    }
    return max(0, -_balances.balance(card.id, until: end) - paid);
  }

  /// Purchases on [card] since its last statement closed, and the
  /// refunds and rewards credited against them.
  List<Entry> unbilled(Account card) => _cache.remember(
    ('unbilled', card.id, closedBy),
    () => _unbilled(card),
    reads: _cardTopics,
  );

  List<Entry> _unbilled(Account card) {
    final (_, end, _) = statement(card);
    bool posted(Entry e) => switch (e.type) {
      EntryType.income => true,
      EntryType.expense => e.installments < 2,
      _ => false,
    };
    return [
      for (final e in _entries.all)
        if (e.account == card.id && posted(e) && e.date.isAfter(end)) e,
    ]..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Purchases on [card] still being paid in instalments.
  List<Entry> instalmentsOn(Account card) => _cache.remember(
    reads: _cardTopics,
    ('instalments', card.id, closedBy),
    () => [
      for (final e in _entries.all)
        if (e.account == card.id &&
            e.installments > 1 &&
            billedPeriods(e, closedBy) < e.installments)
          e,
    ],
  );
}
