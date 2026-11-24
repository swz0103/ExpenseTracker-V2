import 'package:core/foundation_values.dart' show Currency, Money;

import '../journal/store.dart';
import '../model/accounts.dart';
import '../model/day.dart';
import '../model/ids.dart';
import '../model/posting.dart';
import 'contributions.dart';

/// A period's income and spending by account, in the book's own
/// currency, income as positive figures. [foreign] holds the income and
/// spending postings in another currency, which the totals leave out
/// rather than mix in.
typedef PeriodReport = ({
  Map<AccountId, int> income,
  Map<AccountId, int> spending,
  int incomeTotal,
  int spendingTotal,
  List<(AccountId, CurrencyCode, int)> foreign,
});

/// Net worth at a day: each counted asset and liability valued in the
/// book's own currency; [unvalued] are those no valuer could price.
typedef NetWorth = ({
  int assets,
  int liabilities,
  int net,
  Map<AccountId, int> values,
  List<AccountId> unvalued,
});

/// One lot of a holding: its [sub] key, quantity and what it cost.
typedef LotSum = ({String sub, int quantity, int amount});

/// Every figure, read from postings alone: it never sees an intent.
final class BookReader {
  BookReader(this._store, this.accounts, this._contributions, this.home);

  final PostingStore _store;
  final AccountTree accounts;
  final Contributions _contributions;

  /// The currency the book is kept in.
  final CurrencyCode home;

  /// The balance of [account] in [currency] (its own, else the book's)
  /// at the end of [until], or of all time.
  int balance(AccountId account, {Day? until, CurrencyCode? currency}) {
    final c = currency ?? accounts[account]?.currency ?? home;
    return _store.sums(until: until)[(account, c)]?.amount ?? 0;
  }

  /// [balance] as the app's [Money].
  Money balanceMoney(AccountId account, {Day? until, CurrencyCode? currency}) {
    final c = currency ?? accounts[account]?.currency ?? home;
    return Money(
      Currency.of(c.value),
      BigInt.from(balance(account, until: until, currency: c)),
    );
  }

  /// Every balance at the end of [until]: one aggregate.
  AccountSums balances({Day? until}) => _store.sums(until: until);

  /// The quantity [account] holds at the end of [until].
  int quantity(AccountId account, {Day? until}) {
    var total = 0;
    for (final MapEntry(:key, :value) in _store.sums(until: until).entries) {
      if (key.$1 == account) total += value.quantity;
    }
    return total;
  }

  /// The postings on [account] in book order.
  List<Posting> postings(AccountId account) => _store.postingsOf(account);

  /// What the postings on [account] add up to on each day, in day order.
  List<(Day, int)> daySums(AccountId account) => _store.daySums(account);

  /// Every posting of [intent]: its other legs tell where money came
  /// from or went.
  List<Posting> legs(IntentId intent) => _store.postingsOfIntent(intent);

  /// What [account] holds by sub key at the end of [until], in [currency]
  /// (its own, else the book's): a holding's lots, oldest first, those
  /// with nothing left out; or gains by stock.
  List<LotSum> bySub(AccountId account, {Day? until, CurrencyCode? currency}) {
    final c = currency ?? accounts[account]?.currency ?? home;
    return [
      for (final MapEntry(:key, :value)
          in _store.subSums(account, until: until).entries)
        if (key.$2 == c && (value.quantity != 0 || value.amount != 0))
          (sub: key.$1, quantity: value.quantity, amount: value.amount),
    ];
  }

  /// What every currency's postings come to: zero in each, in a sound
  /// book.
  Map<CurrencyCode, int> trialBalance() {
    final total = <CurrencyCode, int>{};
    for (final MapEntry(:key, :value) in _store.sums().entries) {
      total[key.$2] = (total[key.$2] ?? 0) + value.amount;
    }
    return total;
  }

  /// Income and spending from [from] to [to], each counted.
  PeriodReport period(Day from, Day to) {
    final income = <AccountId, int>{};
    final spending = <AccountId, int>{};
    final foreign = <(AccountId, CurrencyCode, int)>[];
    for (final MapEntry(:key, :value)
        in _store.sums(from: from, until: to).entries) {
      final (id, currency) = key;
      final account = accounts[id];
      if (account == null || !account.cls.isFlow) continue;
      if (value.amount == 0 || !account.inFlowReports) continue;
      if (currency != home) {
        foreign.add((id, currency, value.amount));
      } else if (account.cls == AccountClass.income) {
        income[id] = (income[id] ?? 0) - value.amount;
      } else {
        spending[id] = (spending[id] ?? 0) + value.amount;
      }
    }
    int total(Map<AccountId, int> by) => by.values.fold(0, (a, b) => a + b);
    return (
      income: income,
      spending: spending,
      incomeTotal: total(income),
      spendingTotal: total(spending),
      foreign: foreign,
    );
  }

  /// The month [day] falls in.
  PeriodReport month(Day day) => period(day.firstOfMonth, day.lastOfMonth);

  /// [amount] of [unit] in the book's currency, by the first valuer that
  /// knows it.
  int? toHome(String unit, int amount, Day asOf) {
    if (unit == home.value) return amount;
    for (final valuer in _contributions.of(valuers)) {
      final value = valuer(unit, amount, asOf);
      if (value != null) return value;
    }
    return null;
  }

  /// Net worth at the end of [asOf]: a holding is worth its quantity at
  /// a valuer's price, else what it cost.
  NetWorth netWorth(Day asOf) {
    final values = <AccountId, int>{};
    final unvalued = <AccountId>[];
    for (final MapEntry(:key, :value) in _store.sums(until: asOf).entries) {
      final (id, currency) = key;
      final account = accounts[id];
      if (account == null || !account.inNetWorth) continue;
      if (!account.cls.isBalanceSheet) continue;
      final commodity = account.commodity;
      final market = commodity == null
          ? null
          : toHome(commodity, value.quantity, asOf);
      final worth = market ?? toHome(currency.value, value.amount, asOf);
      if (worth == null) {
        if (value.amount != 0) unvalued.add(id);
        continue;
      }
      values[id] = (values[id] ?? 0) + worth;
    }
    var assets = 0;
    var liabilities = 0;
    for (final MapEntry(:key, :value) in values.entries) {
      if (accounts[key]!.cls == AccountClass.asset) {
        assets += value;
      } else {
        liabilities -= value;
      }
    }
    return (
      assets: assets,
      liabilities: liabilities,
      net: assets - liabilities,
      values: values,
      unvalued: unvalued,
    );
  }
}
