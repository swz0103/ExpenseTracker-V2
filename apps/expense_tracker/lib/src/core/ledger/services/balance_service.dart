import '../cache/query_cache.dart';
import 'tracked_readers.dart';
import '../card_cycle.dart';
import '../models/models.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/holding_repository.dart';
import '../repositories/market_data_repository.dart';

/// Balances and worth: each account's on any day, what is owned and owed
/// in all, and how an account moved week by week.
final class BalanceService {
  BalanceService({
    required EntryReader entries,
    required AccountReader accounts,
    required HoldingReader holdings,
    required MarketDataReader market,
    required this._cache,
    required this._today,
  }) : _entries = TrackedEntryReader(entries, _cache),
       _accounts = TrackedAccountReader(accounts, _cache),
       _holdings = TrackedHoldingReader(holdings, _cache),
       _market = TrackedMarketDataReader(market, _cache);

  final EntryReader _entries;
  final AccountReader _accounts;
  final HoldingReader _holdings;
  final MarketDataReader _market;
  final QueryCache _cache;
  final DateTime Function() _today;

  /// What [e] does to [account]'s balance as of today.
  int effect(Entry e, String account) => _effect(e, account, _today());

  /// What [e] does to [account] by the end of [at].
  int _effect(Entry e, String account, DateTime at) =>
      _effectOn(_accounts.resolve(e.account), e, account, at);

  /// [_effect], with the account [e] is paid from, [from], already found.
  static int _effectOn(Account from, Entry e, String account, DateTime at) {
    var change = 0;
    if (e.account == account) {
      change += switch (e.type) {
        EntryType.income => e.amount,
        EntryType.dividend => e.isReduction ? e.amount : e.dividendNet,
        EntryType.sell => e.amount - e.fee - e.tax,
        EntryType.buy || EntryType.transfer => -(e.amount + e.fee),
        EntryType.expense => -from.billed(e, at),
      };
    }
    if (e.type == EntryType.transfer && e.to == account) change += e.arrived;
    return change;
  }

  /// The balance of [account] at the end of [until], or of today.
  int balance(String account, {DateTime? until}) {
    final end = until ?? _today();
    return _cache.remember((
      'balance',
      account,
      end,
    ), () => _balanceOn(account, end));
  }

  int _balanceOn(String account, DateTime end) {
    final running = _cache.remember((
      'running',
      account,
    ), () => _runningOf(account));
    var total = _accounts.resolve(account).opening;
    total += running.until(end);
    for (final e in running.plans) {
      if (!e.date.isAfter(end)) total += _effect(e, account, end);
    }
    return total;
  }

  /// The entries paid from or into each account, in the order written:
  /// one pass over the book, shared by every account asked about.
  Map<String, List<Entry>> _touching() => _cache.remember('touching', () {
    final by = <String, List<Entry>>{};
    for (final e in _entries.all) {
      (by[e.account] ??= []).add(e);
      final to = e.to;
      if (to != null && to != e.account) (by[to] ??= []).add(e);
    }
    return by;
  });

  /// [_Running] for [id], built once per change and only for an account
  /// asked about: only its own entries are put in date order.
  _Running _runningOf(String id) {
    final own = _accounts.resolve(id);
    final running = _Running();
    final days = <int>[];
    final changes = <int>[];
    for (final e in _touching()[id] ?? const <Entry>[]) {
      final from = e.account == id;
      final into = e.type == EntryType.transfer && e.to == id;
      if (!from && !into) continue;
      if (e.type == EntryType.expense && e.installments > 1) {
        // What has been billed depends on the day asked about.
        if (from) running.plans.add(e);
        continue;
      }
      // Anything but an instalment purchase has its full effect at once.
      days.add(e.date.microsecondsSinceEpoch);
      changes.add(_effectOn(own, e, id, e.date));
    }
    final order = List<int>.generate(days.length, (i) => i)
      ..sort((a, b) => days[a].compareTo(days[b]));
    var total = 0;
    for (final i in order) {
      total += changes[i];
      running.days.add(days[i]);
      running.totals.add(total);
    }
    return running;
  }

  /// The balance of [a] in whole NT$; 0 for a foreign account without a
  /// rate, which [unrated] lists.
  int worthOf(Account a, {DateTime? until}) =>
      _market.toHome(balance(a.id, until: until), a.currency) ?? 0;

  /// Counted foreign accounts left out of the totals for want of a rate.
  List<Account> get unrated => [
    for (final a in _accounts.all)
      if (a.foreign && a.inNetWorth && _market.rateOf(a.currency) == null) a,
  ];

  /// What every counted account holds, debts aside, plus investments.
  int get assets {
    var total = _holdings.marketValue;
    for (final a in _accounts.all) {
      if (!a.kind.isDebt && a.inNetWorth) total += worthOf(a);
    }
    return total;
  }

  /// What is owed on cards, as a positive amount.
  int get cardDebt => _owed(AccountKind.card);

  /// What is owed on loans, as a positive amount.
  int get loanDebt => _owed(AccountKind.loan);

  int _owed(AccountKind kind) {
    var total = 0;
    for (final a in _accounts.all) {
      if (a.kind == kind && a.inNetWorth) total += -worthOf(a);
    }
    return total < 0 ? 0 : total;
  }

  /// Counted accounts less debts plus the shares then held at today's
  /// price, at the end of [day].
  int netWorthAt(DateTime day) {
    var total = 0;
    for (final h in _holdings.all) {
      total += (h.price * _holdings.sharesOn(h.code, day)).round();
    }
    for (final a in _accounts.all) {
      if (a.inNetWorth) total += worthOf(a, until: day);
    }
    return total;
  }

  /// The change of [account] in each of the [weeks] calendar weeks
  /// ending with this one, oldest first, with each week's Monday.
  List<(DateTime, int)> weeklyChanges(String account, {int weeks = 4}) =>
      _cache.remember((
        'weekly',
        account,
        weeks,
        _today(),
      ), () => _weeklyChanges(account, weeks));

  List<(DateTime, int)> _weeklyChanges(String account, int weeks) {
    final monday = _today().subtract(Duration(days: _today().weekday - 1));
    final first = monday.subtract(Duration(days: 7 * (weeks - 1)));
    final result = <(DateTime, int)>[];
    for (var w = 0; w < weeks; w++) {
      final start = first.add(Duration(days: 7 * w));
      final end = start.add(const Duration(days: 7));
      var change = 0;
      for (final e in _entries.all) {
        if (!e.date.isBefore(start) && e.date.isBefore(end)) {
          change += _effect(e, account, end);
        }
      }
      result.add((start, change));
    }
    return result;
  }
}

/// One account's entries in date order with the balance change up to each
/// of them, so a balance on any day is one search. Instalment purchases
/// are kept apart: what they have billed depends on the day asked about.
final class _Running {
  /// Each change's day, as microseconds since the epoch, in order.
  final days = <int>[];
  final totals = <int>[];
  final plans = <Entry>[];

  /// The change of the entries on or before [day].
  int until(DateTime day) {
    final end = day.microsecondsSinceEpoch;
    var low = 0;
    var high = days.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (days[middle] > end) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low == 0 ? 0 : totals[low - 1];
  }
}
