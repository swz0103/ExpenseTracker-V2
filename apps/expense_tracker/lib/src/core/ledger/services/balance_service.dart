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
import 'package:core/time/utc_days.dart';

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
  int _effectOn(Account from, Entry e, String account, DateTime at) {
    var change = 0;
    if (e.account == account) {
      change += switch (e.type) {
        EntryType.income => e.amount,
        EntryType.buy || EntryType.sell || EntryType.dividend => e.settlement,
        EntryType.transfer => -(e.amount + e.fee),
        EntryType.expense => -from.billed(e, at),
      };
      for (final (day, billed) in _cancelled(from, e)) {
        if (countsOn(day, at)) change -= billed;
      }
    }
    if (e.type == EntryType.transfer && e.to == account) change += e.arrived;
    return change;
  }

  /// What the refund [e], kept on [from], changes of what [from] is billed
  /// for the purchase in instalments it gives back (`cancelledBy`); empty
  /// for any other entry.
  List<(DateTime, int)> _cancelled(Account from, Entry e) {
    final of = e.refundOf;
    if (of == null || from.kind != AccountKind.card) return const [];
    final purchase = _entries.byId(of);
    if (purchase == null || purchase.installments < 2) return const [];
    return from.cancelledBy(e, purchase, _entries.refundsOf(of));
  }

  /// What of the purchase in instalments [e] is still to be billed after
  /// today, its refunds by today having cancelled what they did: what
  /// the card's balance today does not hold of it yet.
  int stillToBill(Entry e) => _accounts
      .resolve(e.account)
      .stillToBill(e, _entries.refundsOf(e.id), _today());

  /// The balance of [account] at the end of [until], or of today.
  int balance(String account, {DateTime? until}) {
    final end = until ?? _today();
    return _cache.remember((
      'balance',
      account,
      end,
    ), () => _balanceOn(account, end));
  }

  /// The balance of [account] once every entry dated ahead has come: at
  /// the end of the last day an entry may be dated on ([latestEntryDay]).
  /// What archiving a person judges (DEB-01): a lend dated next week
  /// leaves money owed though today's balance is nothing.
  int finalBalance(String account) =>
      balance(account, until: latestEntryDay(_today()));

  /// The day [account]'s last entry dated ahead is on, or today when
  /// none is: the day a settlement before archiving is dated (D120), so
  /// it comes as a planned entry once what is dated ahead has come and
  /// today's balance never shows the opposite of what is left.
  DateTime lastDayAhead(String account) {
    final today = _today();
    final last = latestEntryDay(today);
    for (final e in _entries.ofAccount(account).reversed) {
      if (!e.date.isAfter(today)) break;
      if (!e.date.isAfter(last)) return e.date;
    }
    return today;
  }

  /// The balance of [account] at the end of [end], as [balance] works it
  /// out, but not kept: for a pass over many days, such as the journal's
  /// check, which would fill the cache with answers no screen asks.
  int balanceThrough(String account, DateTime end) => _balanceOn(account, end);

  int _balanceOn(String account, DateTime end) {
    final running = _cache.remember((
      'running',
      account,
    ), () => _runningOf(account));
    var total = _accounts.resolve(account).opening;
    return total + running.until(end);
  }

  /// The entries paid from or into [account], newest first: from the
  /// index the entries keep by account, rather than a pass over every
  /// entry.
  List<Entry> entriesOf(String account) =>
      // Exception to as-of-today: the account's list shows 預定 entries marked.
      List.unmodifiable(_entries.ofAccount(account).reversed);

  /// What came into [account] and what left it in [month] (the month of
  /// that day), each as a positive amount in its currency, as of today:
  /// the changes of its balance on the days of the month, so a purchase
  /// in instalments leaves as its statements bill it.
  ({int inflow, int outflow}) flowOf(String account, DateTime month) {
    final today = _today();
    return _cache.remember(
      ('flow', account, month.year, month.month, today),
      () {
        var inflow = 0;
        var outflow = 0;
        final first = DateTime.utc(month.year, month.month);
        final last = monthEnd(month.year, month.month);
        for (final (day, change) in _runningOf(
          account,
        ).changesIn(first, last)) {
          if (!countsOn(day, today)) continue;
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
    // Exception to as-of-today: every change is kept on its day; a balance
    // counts those that count on its own ([_Running.until]).
    for (final e in _entries.ofAccount(id)) {
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
      // A refund cancelling instalments: what it cancels is billed on
      // the days the rule says, apart from the refund itself.
      final cancelled = from ? _cancelled(own, e) : const <(DateTime, int)>[];
      if (cancelled.isNotEmpty) {
        steps.add((e.date.microsecondsSinceEpoch, e.amount));
        for (final (day, billed) in cancelled) {
          steps.add((day.microsecondsSinceEpoch, -billed));
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

  /// The balance of [a] in whole NT$, held at the bank's buying rate and
  /// owed at its selling rate (D59); 0 for a foreign account without a
  /// rate, which [unrated] lists.
  int worthOf(Account a, {DateTime? until}) =>
      _market.valueAtHome(balance(a.id, until: until), a.currency) ?? 0;

  /// Counted foreign accounts left out of the totals for want of a rate.
  List<Account> get unrated => [
    for (final a in _accounts.all)
      if (a.foreign && a.inNetWorth && _market.rateOf(a.currency) == null) a,
  ];

  /// What the book is worth at the end of [day], and what it is made of:
  /// the one net worth every screen shows (D63), the accounts' hero, its
  /// change since last month, the overview's chart and the reports. Each
  /// counted account stands on the side its balance is on, whatever its
  /// kind: a card or a loan paid past what it owed is money held, a bank
  /// account overdrawn is owed. The shares then held count at today's
  /// price (D105), those of a stock sold since included, until the
  /// prices of past days are kept.
  NetWorth netWorth(DateTime day) {
    var invested = 0;
    for (final h in _holdings.every) {
      invested += timesPrice(_holdings.sharesOn(h.code, day), h.price);
    }
    var saved = 0;
    var lent = 0;
    var owed = 0;
    for (final a in _accounts.all) {
      if (!a.inNetWorth) continue;
      final worth = worthOf(a, until: day);
      if (worth < 0) {
        owed -= worth;
      } else if (a.kind == AccountKind.receivable) {
        lent += worth;
      } else {
        saved += worth;
      }
    }
    return NetWorth(saved: saved, invested: invested, lent: lent, owed: owed);
  }

  /// [netWorth] at the end of [day], as one sum.
  int netWorthAt(DateTime day) => netWorth(day).net;

  /// What every counted account holds today, plus investments: the
  /// held side of [netWorth].
  int get assets => netWorth(_today()).held;

  /// What is owed on cards today, as a positive amount: the cards' part
  /// of what [netWorth] counts owed.
  int get cardDebt => _owed(AccountKind.card);

  /// What is owed on loans today, as a positive amount: the loans' part
  /// of what [netWorth] counts owed.
  int get loanDebt => _owed(AccountKind.loan);

  int _owed(AccountKind kind) {
    var total = 0;
    for (final a in _accounts.all) {
      if (a.kind != kind || !a.inNetWorth) continue;
      final worth = worthOf(a);
      if (worth < 0) total -= worth;
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

  /// How [account]'s balance moved in each week: from the end of the day
  /// before it to the end of its last day, or of today for this week.
  List<(DateTime, int)> _weeklyChanges(String account, int weeks) {
    final today = _today();
    final first = startOfWeek(BusinessDate.of(today)).asUtcMidnight
        .subtract(Duration(days: 7 * (weeks - 1)));
    final running = _runningOf(account);
    final result = <(DateTime, int)>[];
    for (var w = 0; w < weeks; w++) {
      final start = first.add(Duration(days: 7 * w));
      final last = start.add(const Duration(days: 6));
      final end = last.isAfter(today) ? today : last;
      final change =
          running.until(end) -
          running.until(start.subtract(const Duration(days: 1)));
      result.add((start, change));
    }
    return result;
  }
}

/// What a book is worth on a day ([BalanceService.netWorth]), by side:
/// what is held, in accounts ([saved]), in shares ([invested]) and lent
/// to people ([lent]), and what is [owed], each in whole NT$ and none
/// below zero.
final class NetWorth {
  const NetWorth({
    required this.saved,
    required this.invested,
    required this.lent,
    required this.owed,
  });

  final int saved;
  final int invested;
  final int lent;
  final int owed;

  /// Everything held.
  int get held => saved + invested + lent;

  /// What is held less what is owed.
  int get net => held - owed;
}

/// One account's changes in date order with the balance up to each of
/// them, so a balance on any day is one search. A purchase in instalments
/// is a change on each day one of its statements closes.
final class _Running {
  /// Each change's day, as microseconds since the epoch, in order.
  final days = <int>[];
  final totals = <int>[];

  /// Each change's day and amount from [first] to [last], both days
  /// included, in order: found by a search, not a pass over every change.
  Iterable<(DateTime, int)> changesIn(DateTime first, DateTime last) sync* {
    final from = _firstAtOrAfter(first.microsecondsSinceEpoch);
    final to = _firstAtOrAfter(last.microsecondsSinceEpoch + 1);
    for (var i = from; i < to; i++) {
      yield (
        DateTime.fromMicrosecondsSinceEpoch(days[i], isUtc: true),
        totals[i] - (i == 0 ? 0 : totals[i - 1]),
      );
    }
  }

  /// The place of the first change on or after [day] (microseconds).
  int _firstAtOrAfter(int day) {
    var low = 0;
    var high = days.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (days[middle] < day) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

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
