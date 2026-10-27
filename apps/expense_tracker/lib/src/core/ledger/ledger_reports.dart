part of 'ledger.dart';

/// Sums the screens show: any stretch of days, balances and worth,
/// merchants and tags, and amounts in other currencies.
extension LedgerReports on Ledger {
  Iterable<Entry> _between(DateTime from, DateTime to) =>
      _entries.where((e) => !e.date.isBefore(from) && !e.date.isAfter(to));

  /// Income, dividends included, and spending from [from] to [to].
  (int, int) totalsBetween(DateTime from, DateTime to) {
    var income = 0;
    var expense = 0;
    for (final e in _between(from, to)) {
      income += e.earning;
      expense += e.spending;
    }
    return (income, expense);
  }

  int dividendsBetween(DateTime from, DateTime to) =>
      _between(from, to).fold(0, (sum, e) => sum + e.dividendNet);

  /// Spending by category name from [from] to [to].
  Map<String, int> spendingBetween(DateTime from, DateTime to) {
    final totals = <String, int>{};
    for (final e in _between(from, to)) {
      for (final (name, value) in e.spendingParts) {
        totals[name] = (totals[name] ?? 0) + value;
      }
    }
    return totals;
  }

  /// Spending by merchant from [from] to [to], largest first, with how
  /// many times each was paid.
  List<(String, int, int)> merchantsBetween(DateTime from, DateTime to) {
    final amounts = <String, int>{};
    final counts = <String, int>{};
    for (final e in _between(from, to)) {
      if (e.type != EntryType.expense || e.merchant.isEmpty) continue;
      amounts[e.merchant] = (amounts[e.merchant] ?? 0) + e.spending;
      counts[e.merchant] = (counts[e.merchant] ?? 0) + 1;
    }
    final rows = [
      for (final MapEntry(:key, :value) in amounts.entries)
        (key, counts[key] ?? 0, value),
    ];
    rows.sort((a, b) => b.$3.compareTo(a.$3));
    return rows;
  }

  /// Spending by tag from [from] to [to], largest first.
  List<(String, int)> tagsBetween(DateTime from, DateTime to) {
    final totals = <String, int>{};
    for (final e in _between(from, to)) {
      if (e.spending == 0) continue;
      for (final tag in e.tags) {
        totals[tag] = (totals[tag] ?? 0) + e.spending;
      }
    }
    final rows = [
      for (final MapEntry(:key, :value) in totals.entries) (key, value),
    ];
    rows.sort((a, b) => b.$2.compareTo(a.$2));
    return rows;
  }

  /// The day of the first entry, where the book starts.
  DateTime get firstDay => _first ??= _firstDay();

  DateTime _firstDay() => _entries.isEmpty
      ? today
      : _entries.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);

  /// What [e] does to [account]'s balance as of today.
  int effect(Entry e, String account) => _effect(e, account, today);

  /// What [e] does to [account] by the end of [at].
  int _effect(Entry e, String account, DateTime at) {
    var change = 0;
    if (e.account == account) {
      change += switch (e.type) {
        EntryType.income => e.amount,
        EntryType.dividend => e.isReduction ? e.amount : e.dividendNet,
        EntryType.sell => e.amount - e.fee - e.tax,
        EntryType.buy || EntryType.transfer => -(e.amount + e.fee),
        EntryType.expense => -billed(e, at),
      };
    }
    if (e.type == EntryType.transfer && e.to == account) change += e.arrived;
    return change;
  }

  /// Known merchants, most used first.
  List<String> get merchants =>
      _remember('merchants', _merchants, on: const {Area.entries});

  List<String> _merchants() {
    final counts = <String, int>{};
    for (final e in _entries) {
      if (e.merchant.isEmpty) continue;
      counts[e.merchant] = (counts[e.merchant] ?? 0) + 1;
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  /// The category last used with [merchant], if any.
  String? categoryAt(String merchant) => _remember('categoryAt', () {
    final latest = <String, Entry>{};
    for (final e in _entries) {
      if (e.merchant.isEmpty || e.type != EntryType.expense) continue;
      final kept = latest[e.merchant];
      if (kept == null || e.date.isAfter(kept.date)) latest[e.merchant] = e;
    }
    return {
      for (final MapEntry(:key, :value) in latest.entries) key: value.category,
    };
  }, on: const {Area.entries})[merchant];

  /// Every tag with how many entries carry it and their spending, most
  /// used first.
  List<(String, int, int)> get tagStats =>
      _remember('tagStats', _tagStats, on: const {Area.entries});

  List<(String, int, int)> _tagStats() {
    final counts = <String, int>{};
    final sums = <String, int>{};
    for (final e in _entries) {
      for (final tag in e.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
        sums[tag] = (sums[tag] ?? 0) + e.spending;
      }
    }
    return [
      for (final MapEntry(:key, :value) in counts.entries)
        (key, value, sums[key] ?? 0),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
  }

  /// Every merchant with how many entries name it and their spending,
  /// most used first.
  List<(String, int, int)> get merchantStats =>
      merchantsBetween(firstDay, today)..sort((a, b) => b.$2.compareTo(a.$2));

  /// Every tag in use, most used first.
  List<String> get tags => [for (final (tag, _, _) in tagStats) tag];

  /// Every trade and dividend of [code], newest first.
  List<Entry> tradesOf(String code) => [
    for (final e in _entries)
      if (e.holding == code) e,
  ]..sort((a, b) => b.date.compareTo(a.date));

  /// The entry with [id], if it is still in the book.
  Entry? byId(String id) =>
      (_idIndex ??= {for (final e in _entries) e.id: e})[id];

  /// How much of [original] is left to refund.
  int refundable(Entry original) {
    final back = _refundIndex ??= () {
      final sums = <String, int>{};
      for (final e in _entries) {
        if (e.refundOf case final of?) sums[of] = (sums[of] ?? 0) + e.amount;
      }
      return sums;
    }();
    return original.amount - (back[original.id] ?? 0);
  }

  /// The balance of [account] at the end of [until], or of today.
  int balance(String account, {DateTime? until}) {
    final end = until ?? today;
    return _balances[(account, end)] ??= _balanceOn(account, end);
  }

  int _balanceOn(String account, DateTime end) {
    final running = (_running ??= _runningTotals())[account];
    var total = this.account(account).opening;
    if (running == null) return total;
    total += running.until(end);
    for (final e in running.plans) {
      if (!e.date.isAfter(end)) total += _effect(e, account, end);
    }
    return total;
  }

  /// [_Running] for every account an entry touches, built once per change.
  Map<String, _Running> _runningTotals() {
    final changes = <String, List<(DateTime, int)>>{};
    final running = <String, _Running>{};
    for (final e in _entries) {
      for (final id in {e.account, ?e.to}) {
        final kept = running[id] ??= _Running();
        if (e.type == EntryType.expense && e.installments > 1) {
          if (id == e.account) kept.plans.add(e);
          continue;
        }
        // Anything but an instalment purchase has its full effect at once.
        (changes[id] ??= []).add((e.date, _effect(e, id, e.date)));
      }
    }
    for (final MapEntry(key: id, value: list) in changes.entries) {
      list.sort((a, b) => a.$1.compareTo(b.$1));
      final kept = running[id]!;
      var total = 0;
      for (final (day, change) in list) {
        total += change;
        kept.days.add(day);
        kept.totals.add(total);
      }
    }
    return running;
  }

  int get investValue => _holdings.fold(0, (sum, h) => sum + h.value);
  int get investCost => _holdings.fold(0, (sum, h) => sum + h.cost);
  int get dayChange => _holdings.fold(0, (sum, h) => sum + h.change);
  int get realized => _holdings.fold(0, (sum, h) => sum + h.realized);
  int get totalDividends => _holdings.fold(0, (sum, h) => sum + h.dividends);

  /// Accounts still open, in their order.
  List<Account> get openAccounts => [
    for (final a in _accounts)
      if (!a.archived) a,
  ];

  /// The account money usually comes from or goes back to, as for a card
  /// payment or money paid back: the first open NT$ bank account, else
  /// any open NT$ account that is not a debt; empty when there is none.
  String get mainAccount {
    final open = [
      for (final a in openAccounts)
        if (!a.kind.isDebt && !a.foreign && a.kind != AccountKind.receivable) a,
    ];
    for (final a in open) {
      if (a.kind == AccountKind.bank) return a.id;
    }
    return open.isEmpty ? '' : open.first.id;
  }

  // Currencies.

  /// NT$ for one unit of each foreign currency: 臺灣銀行's spot buying
  /// rate, what a foreign balance would fetch today. Empty until fetched.
  Map<String, double> get rates => Map.unmodifiable(_rates);

  /// [minor] units of [currency] in whole NT$ at [rates]; null without a
  /// rate for it.
  int? toHome(int minor, String currency) {
    if (currency == homeCode) return minor;
    final rate = _rates[currency];
    if (rate == null) return null;
    return (minor / _unit(currency) * rate).round();
  }

  /// [amount] of [from] in the smallest unit of [to], through NT$ at
  /// [rates]; null without a rate for either.
  int? convert(int amount, String from, String to) {
    if (from == to) return amount;
    final home = from == homeCode ? amount.toDouble() : _rated(amount, from);
    if (home == null) return null;
    if (to == homeCode) return home.round();
    final rate = _rates[to];
    if (rate == null || rate <= 0) return null;
    return (home / rate * _unit(to)).round();
  }

  double? _rated(int minor, String currency) {
    final rate = _rates[currency];
    return rate == null ? null : minor / _unit(currency) * rate;
  }

  static int _unit(String currency) =>
      Currency.scaleOf(currency) == 0 ? 1 : 100;

  /// The balance of [a] in whole NT$; 0 for a foreign account without a
  /// rate, which [unrated] lists.
  int worthOf(Account a, {DateTime? until}) =>
      toHome(balance(a.id, until: until), a.currency) ?? 0;

  /// Counted foreign accounts left out of the totals for want of a rate.
  List<Account> get unrated => [
    for (final a in _accounts)
      if (a.foreign && a.inNetWorth && !_rates.containsKey(a.currency)) a,
  ];

  /// What every counted account holds, debts aside, plus investments.
  int get assets {
    var total = investValue;
    for (final a in _accounts) {
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
    for (final a in _accounts) {
      if (a.kind == kind && a.inNetWorth) total += -worthOf(a);
    }
    return total < 0 ? 0 : total;
  }

  /// Counted accounts less debts plus the shares then held at today's
  /// price, at the end of [day].
  int netWorthAt(DateTime day) {
    var total = 0;
    for (final h in _holdings) {
      total += (h.price * _portfolio.sharesOn(h.code, day)).round();
    }
    for (final a in _accounts) {
      if (a.inNetWorth) total += worthOf(a, until: day);
    }
    return total;
  }

  /// The change of [account] in each of the [weeks] calendar weeks
  /// ending with this one, oldest first, with each week's Monday.
  List<(DateTime, int)> weeklyChanges(String account, {int weeks = 4}) =>
      _remember((
        'weekly',
        account,
        weeks,
        today,
      ), () => _weeklyChanges(account, weeks), on: _cardAreas);

  List<(DateTime, int)> _weeklyChanges(String account, int weeks) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final first = monday.subtract(Duration(days: 7 * (weeks - 1)));
    final result = <(DateTime, int)>[];
    for (var w = 0; w < weeks; w++) {
      final start = first.add(Duration(days: 7 * w));
      final end = start.add(const Duration(days: 7));
      var change = 0;
      for (final e in _entries) {
        if (!e.date.isBefore(start) && e.date.isBefore(end)) {
          change += _effect(e, account, end);
        }
      }
      result.add((start, change));
    }
    return result;
  }

  /// Open spending or [income] categories, the most used over this month
  /// and the last first, so a new entry starts on the likely one.
  List<String> categoriesByUse({required bool income}) {
    final type = income ? EntryType.income : EntryType.expense;
    final counts = <String, int>{};
    for (final back in const [0, 1]) {
      final month = DateTime.utc(today.year, today.month - back);
      for (final e in entriesIn(month.year, month.month)) {
        if (e.type == type) counts[e.category] = (counts[e.category] ?? 0) + 1;
      }
    }
    final names = [for (final c in categoriesFor(income: income)) c.name];
    return names..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
  }
}
