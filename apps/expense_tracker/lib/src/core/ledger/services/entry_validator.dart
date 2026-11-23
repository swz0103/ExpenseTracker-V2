import 'package:ledger_entries/rules.dart';

import '../models/models.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/holding_repository.dart';
import 'balance_service.dart';
import 'entry_query_service.dart';

/// Asks the ledger's write rules (package ledger_entries) about an entry,
/// with the facts of this book they need: the accounts it names, the
/// shares and refund it touches, the paying account's balance. The rules
/// decide; this only looks the facts up. Every command that writes an
/// entry asks here first, and so does every form, before it is asked.
final class EntryValidator {
  EntryValidator({
    required this._entries,
    required this._accounts,
    required this._holdings,
    required EntryQueryService entryQueryService,
    required BalanceService balanceService,
  }) : _entryQueries = entryQueryService,
       _balances = balanceService;

  final EntryReader _entries;
  final AccountReader _accounts;
  final HoldingReader _holdings;
  final EntryQueryService _entryQueries;
  final BalanceService _balances;

  /// The first reason [e] cannot be kept; null when it can, warnings
  /// aside. [replacing] is the entry [e] edits, whose own shares and
  /// refund do not count against it. An import, and a command that replays
  /// the trades after, checks the shares together ([holdings] false);
  /// [opening] are accounts an import brings, not in the book yet.
  RecordIssue? validate(
    Entry e, {
    Entry? replacing,
    bool holdings = true,
    Iterable<Account> opening = const [],
  }) {
    for (final issue in issues(
      e,
      replacing: replacing,
      holdings: holdings,
      opening: opening,
    )) {
      if (issue.isError) return issue;
    }
    return null;
  }

  /// Everything the rules say about keeping [e], warnings included, as
  /// [validate] asks.
  List<RecordIssue> issues(
    Entry e, {
    Entry? replacing,
    bool holdings = true,
    Iterable<Account> opening = const [],
  }) {
    AccountFacts? facts(String? id) {
      if (id == null) return null;
      final a =
          _accounts.byId(id) ?? opening.where((a) => a.id == id).firstOrNull;
      return a == null ? null : AccountFacts(a.kind, currency: a.currency);
    }

    final original = e.refundOf == null ? null : _entries.byId(e.refundOf!);
    return entryIssues(
      e,
      EntryFacts(
        account: facts(e.account),
        to: facts(e.to),
        heldBefore: holdings && e.isReduction
            ? _heldBefore(e.holding ?? '', replacing)
            : null,
        oversells:
            holdings &&
            (e.type == EntryType.sell || e.isReduction) &&
            !holdsWith([e], replacing: replacing),
        refunded: original == null
            ? null
            : RefundFacts(
                account: original.account,
                kind: _accounts.resolve(original.account).kind,
                left: _entryQueries.refundable(original),
                own: replacing?.refundOf == e.refundOf ? replacing!.amount : 0,
              ),
        balanceAfter: e.type == EntryType.buy && _accounts.contains(e.account)
            ? _balanceAfter(e, replacing)
            : null,
      ),
    );
  }

  /// The balance of [e]'s account today once [e] is kept in place of
  /// [replacing].
  int _balanceAfter(Entry e, Entry? replacing) =>
      _balances.balance(e.account) -
      (replacing == null ? 0 : _balances.effect(replacing, e.account)) +
      _balances.effect(e, e.account);

  /// The shares of [code] held before [replacing], when that one is a
  /// reduction of them.
  int _heldBefore(String code, Entry? replacing) {
    final held = _holdings.byCode(code)?.shares ?? 0;
    if (replacing == null ||
        !replacing.isReduction ||
        replacing.holding != code) {
      return held;
    }
    return held - replacing.shares;
  }

  /// Whether [extra] can join the entries, in place of [replacing]: none
  /// of their trades sells more shares than are held by then.
  bool holdsWith(List<Entry> extra, {Entry? replacing}) {
    return _holdings.holdsWith([
      for (final e in _entries.all)
        if (replacing == null || e.id != replacing.id) e,
      ...extra,
    ]);
  }
}
