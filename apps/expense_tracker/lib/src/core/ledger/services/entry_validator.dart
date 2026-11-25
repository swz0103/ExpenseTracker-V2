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
    this._today,
  }) : _entryQueries = entryQueryService,
       _balances = balanceService;

  final EntryReader _entries;
  final AccountReader _accounts;
  final HoldingReader _holdings;
  final EntryQueryService _entryQueries;
  final BalanceService _balances;

  /// Today, for how far ahead an entry may be dated (D25); null leaves
  /// its day unchecked.
  final DateTime Function()? _today;

  /// The first reason [e] cannot be kept; null when it can, warnings
  /// aside. [replacing] is the entry [e] edits, whose own shares and
  /// refund do not count against it. An import, and a command that replays
  /// the trades after, checks the shares together ([holdings] false);
  /// [opening] are accounts an import brings, not in the book yet;
  /// [refunding] the spending a refund it reads gives back, the book's or
  /// one of the same file, with what is left of it once the refunds read
  /// before are given (review 37 1).
  RecordIssue? validate(
    Entry e, {
    Entry? replacing,
    bool holdings = true,
    Iterable<Account> opening = const [],
    ({Entry original, int left})? refunding,
  }) {
    for (final issue in issues(
      e,
      replacing: replacing,
      holdings: holdings,
      opening: opening,
      refunding: refunding,
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
    ({Entry original, int left})? refunding,
  }) {
    Account? account(String id) =>
        _accounts.byId(id) ?? opening.where((a) => a.id == id).firstOrNull;
    AccountFacts? facts(String? id) {
      if (id == null) return null;
      final a = account(id);
      return a == null ? null : AccountFacts(a.kind, currency: a.currency);
    }

    final given = refunding?.original.id == e.refundOf ? refunding : null;
    final original =
        given?.original ??
        (e.refundOf == null ? null : _entries.byId(e.refundOf!));
    final RefundFacts? refunded;
    if (original == null) {
      refunded = null;
    } else {
      final paid =
          account(original.account) ?? _accounts.resolve(original.account);
      refunded = RefundFacts(
        account: original.account,
        kind: paid.kind,
        currency: paid.currency,
        left: given?.left ?? _entryQueries.refundable(original),
        own: replacing?.refundOf == e.refundOf ? replacing!.amount : 0,
      );
    }
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
        refunded: refunded,
        balanceAfter: e.type == EntryType.buy && _accounts.contains(e.account)
            ? _balanceAfter(e, replacing)
            : null,
        today: _today?.call(),
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
  /// of their trades sells more shares than are held by then. A stock's
  /// holdings are worked out from its own trades alone (as [TradeRun]
  /// does): only the stocks [extra] and [replacing] trade are replayed
  /// with the change; every other one as the book has it, answered once
  /// until a trade of it changes ([HoldingReader.holdsWithKept]), so a
  /// save does not replay the whole book (FIX-R34).
  bool holdsWith(List<Entry> extra, {Entry? replacing}) {
    final changed = <String, List<Entry>>{};
    if (replacing != null) {
      if (TradeRun._codeOf(replacing) case final code?) changed[code] = [];
    }
    for (final e in extra) {
      if (TradeRun._codeOf(e) case final code?) (changed[code] ??= []).add(e);
    }
    // Exception to as-of-today: the write rules check the whole timeline,
    // so no change leaves a later sale short.
    for (final code in _entries.holdingCodes) {
      if (changed.containsKey(code)) continue;
      // Exception to as-of-today: the whole timeline, as above.
      if (!_holdings.holdsWithKept(_entries.ofHolding(code))) return false;
    }
    for (final MapEntry(key: code, value: added) in changed.entries) {
      final trades = [
        // Exception to as-of-today: the whole timeline, as above.
        for (final e in _entries.ofHolding(code))
          if (replacing == null || e.id != replacing.id) e,
        ...added,
      ];
      if (!_holdings.holdsWith(trades)) return false;
    }
    return true;
  }

  /// Answers, ahead of the first save of a trade, what [holdsWith] keeps
  /// for every stock the book trades: the index of the entries by stock
  /// first, then each stock's holdings as the book has them, one stock at
  /// a time, [goOn] awaited before each step (the app runs each between
  /// frames, once the book is on the screen), and no more steps once it
  /// answers false. Made at the first save, these held it about 50 ms at
  /// 100,000 entries (FIX-R34). A book changed meanwhile only makes a
  /// step answer the stock as it stands.
  Future<void> prepare(Future<bool> Function() goOn) async {
    if (!await goOn()) return;
    final codes = _entries.holdingCodes.toList();
    for (final code in codes) {
      if (!await goOn()) return;
      // Exception to as-of-today: the whole timeline, as holdsWith asks.
      _holdings.holdsWithKept(_entries.ofHolding(code));
    }
  }

  /// Trades checked one after another, as an import reads them: each
  /// against the book and the trades [TradeRun.add]ed before it.
  TradeRun tradeRun() => TradeRun._(_holdings, _entries);
}

/// Trades checked one after another against the book, oldest first, as an
/// import reads them (review 32 1.6): [holds] answers as
/// [EntryValidator.holdsWith] given every trade [add]ed so far and the one
/// asked about, without replaying the whole book for each. A stock's
/// holdings are worked out from its own trades alone, so only the asked
/// one's stock is replayed; every other stock's answer is kept until a
/// trade of it is added.
final class TradeRun {
  TradeRun._(this._holdings, EntryReader entries) {
    // Exception to as-of-today: the write rules check the whole timeline,
    // as holdsWith does.
    for (final e in entries.all) {
      if (_codeOf(e) case final code?) (_trades[code] ??= []).add(e);
    }
  }

  final HoldingReader _holdings;

  /// Each stock's trades, the book's in the order written, then those
  /// added, in turn: as holdsWith lists them, less the other stocks'.
  final _trades = <String, List<Entry>>{};

  /// Whether each stock's trades hold as they stand; worked out when
  /// first asked, again once a trade of it is added.
  final _holds = <String, bool>{};

  /// The stock a trade is replayed under; null for an entry no replay
  /// reads.
  static String? _codeOf(Entry e) => e.isInvestment ? e.holding : null;

  bool _stands(String code) =>
      _holds[code] ??= _holdings.holdsWith(_trades[code] ?? const []);

  /// Whether [e] can join the book after the trades added so far: none
  /// of them sells more shares than are held by then.
  bool holds(Entry e) {
    final own = _codeOf(e);
    for (final code in _trades.keys) {
      if (code != own && !_stands(code)) return false;
    }
    if (own == null) return true;
    return _holdings.holdsWith([...?_trades[own], e]);
  }

  /// Takes [e] as one of the trades the next are checked after.
  void add(Entry e) {
    final code = _codeOf(e);
    if (code == null) return;
    (_trades[code] ??= []).add(e);
    _holds.remove(code);
  }
}
