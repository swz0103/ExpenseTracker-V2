import 'package:core/money/price.dart' show timesPrice;

import '../cache/query_cache.dart';
import 'tracked_readers.dart';
import '../card_cycle.dart';
import '../models/models.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/holding_repository.dart';
import '../repositories/market_data_repository.dart';

import 'package:core/foundation_values.dart' show BusinessDate, startOfWeek;

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
        EntryType.buy || EntryType.sell || EntryType.dividend => e.settlement,
        EntryType.transfer => -(e.amount + e.fee),
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
    return total + running.until(end);
  }

  /// The entries paid from or into each account, oldest day first: one
  /// pass over the book in date order, shared by every account asked
  /// about, so no account's entries need sorting.
  Map<String, List<Entry>> _touching() => _cache.remember('touching', () {
    final by = <String, List<Entry>>{};
    for (final e in _entries.byDate) {
      (by[e.account] ??= []).add(e);
      final to = e.to;
      if (to != null && to != e.account) (by[to] ??= []).add(e);
    }
    return by;
  });

  /// The entries paid from or into [account], newest first: from the
  /// index the balances keep, rather than a pass over every entry.
  List<Entry> entriesOf(String account) =>
      List.unmodifiable((_touching()[account] ?? const <Entry>[]).reversed);

  /// What came into [account] and what left it in [month] (the month of
  /// that day), each as a positive amount in its currency, as of today.
  ({int inflow, int outflow}) flowOf(String account, DateTime month) {
    final today = _today();
    return _cache.remember(
      ('flow', account, month.year, month.month, today),
      () {
        var inflow = 0;
        var outflow = 0;
        for (final e in countedOn(
          _entries.inMonth(month.year, month.month),
          today,
        )) {
          if (e.account != account && e.to != account) continue;
          final change = _effect(e, account, today);
          if (change > 0) {
            inflow += change;
          } else {
            outflow -= change;
          }
        }
        return (inflow: inflow, outflow: outflow);
      },
    );
  }

  /// Each account's [_Running] as last built, with the account and the
  /// version of its entries it was built from ([EntryReader.versionOf]).
  /// Any change to the entries throws away the cached answers of every
  /// account; this keeps those of the accounts the change did not touch,
  /// so a save costs the accounts it moves, not every account's entries
  /// again (with 100,000 entries, every account was rebuilt per save).
  final _built = <String, (int, Account, _Running)>{};

  /// [_Running] for [id], built once per change of its own entries and
  /// only for an account asked about, from them already in date order.
  _Running _runningOf(String id) {
    final own = _accounts.resolve(id);
    final version = _entries.versionOf(id);
    if (_built[id] case (final was, final from, final kept)
        when was == version && identical(from, own)) {
      return kept;
    }
    final running = _buildRunning(id, own);
    _built[id] = (version, own, running);
    return running;
  }

  _Running _buildRunning(String id, Account own) {
    final days = <int>[];
    final changes = <int>[];
    // Instalments, each billed when its statement closes: few, and out of
    // the entries' order, so sorted apart and merged in.
    final steps = <(int, int)>[];
    for (final e in _touching()[id] ?? const <Entry>[]) {
      final from = e.account == id;
      final into = e.type == EntryType.transfer && e.to == id;
      if (!from && !into) continue;
      if (e.type == EntryType.expense && e.installments > 1) {
        if (from) {
          for (final (day, share) in own.billingSteps(e)) {
            steps.add((day.microsecondsSinceEpoch, -share));
          }
        }
        continue;
      }
      // Anything but an instalment purchase has its full effect at once.
      days.add(e.date.microsecondsSinceEpoch);
      changes.add(_effectOn(own, e, id, e.date));
    }
    steps.sort((a, b) => a.$1.compareTo(b.$1));
    final running = _Running();
    var total = 0;
    var i = 0;
    var k = 0;
    while (i < days.length || k < steps.length) {
      final int day;
      if (k == steps.length || (i < days.length && days[i] <= steps[k].$1)) {
        day = days[i];
        total += changes[i++];
      } else {
        day = steps[k].$1;
        total += steps[k++].$2;
      }
      running.days.add(day);
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
      total += timesPrice(_holdings.sharesOn(h.code, day), h.price);
    }
    for (final a in _accounts.all) {
      if (a.inNetWorth) total += worthOf(a, until: day);
    }
    return total;
  }

  /// The change of [account] in each of the [weeks] calendar weeks
  /// ending with this one, oldest first, with the Sunday each starts on.
  List<(DateTime, int)> weeklyChanges(String account, {int weeks = 4}) =>
      _cache.remember((
        'weekly',
        account,
        weeks,
        _today(),
      ), () => _weeklyChanges(account, weeks));

  List<(DateTime, int)> _weeklyChanges(String account, int weeks) {
    final first = startOfWeek(BusinessDate.of(_today())).asUtcMidnight
        .subtract(Duration(days: 7 * (weeks - 1)));
    final result = <(DateTime, int)>[];
    for (var w = 0; w < weeks; w++) {
      final start = first.add(Duration(days: 7 * w));
      final end = start.add(const Duration(days: 7));
      var change = 0;
      for (final e in countedOn(_entries.all, _today())) {
        if (!e.date.isBefore(start) && e.date.isBefore(end)) {
          change += _effect(e, account, end);
        }
      }
      result.add((start, change));
    }
    return result;
  }
}

/// One account's changes in date order with the balance up to each of
/// them, so a balance on any day is one search. A purchase in instalments
/// is a change on each day one of its statements closes.
final class _Running {
  /// Each change's day, as microseconds since the epoch, in order.
  final days = <int>[];
  final totals = <int>[];

  /// The change of the entries that count on [day] ([countsOn]): those
  /// on or before it, so a balance as of today leaves 預定 entries out
  /// until their day (D25).
  int until(DateTime day) {
    var low = 0;
    var high = days.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      final at = DateTime.fromMicrosecondsSinceEpoch(days[middle], isUtc: true);
      if (!countsOn(at, day)) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low == 0 ? 0 : totals[low - 1];
  }
}
