import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:foundation_values/foundation_values.dart'
    show Currency, PublicId;

import '../book/journal.dart';
import '../look/figures.dart';

/// What an entry does. Buys, sells and dividends are investment entries.
enum EntryType { expense, income, transfer, buy, sell, dividend }

enum AccountKind {
  cash,
  bank,
  wallet,
  card,
  loan,
  receivable;

  /// Kinds whose balance is owed rather than held.
  bool get isDebt => this == card || this == loan;
}

final class Account {
  const Account(
    this.id,
    this.name,
    this.kind,
    this.opening, {
    this.icon,
    this.closingDay,
    this.dueDay,
    this.limit,
    this.archived = false,
    this.inNetWorth = true,
    this.currency = 'TWD',
  });

  final String id;
  final String name;
  final AccountKind kind;

  /// What the account is kept in, such as TWD or USD. Its [opening], its
  /// entries and its balance count the smallest unit of it: whole NT$,
  /// US cents.
  final String currency;

  /// Kept in a currency other than NT$.
  bool get foreign => currency != 'TWD';

  /// The account's own mark, such as 'safe' or 'chat'; null takes the
  /// mark of its [kind].
  final String? icon;

  /// The balance before the first entry; negative for card debt.
  final int opening;

  /// A card's statement closing day and payment day of the month, and
  /// its credit limit.
  final int? closingDay;
  final int? dueDay;
  final int? limit;

  /// Closed and kept only for its history: left out of lists and pickers.
  final bool archived;

  /// Counted in the totals and net worth.
  final bool inNetWorth;

  Account copyWith({
    String? name,
    AccountKind? kind,
    int? opening,
    String? icon,
    int? closingDay,
    int? dueDay,
    int? limit,
    bool? archived,
    bool? inNetWorth,
  }) => Account(
    id,
    name ?? this.name,
    kind ?? this.kind,
    opening ?? this.opening,
    icon: icon ?? this.icon,
    closingDay: closingDay ?? this.closingDay,
    dueDay: dueDay ?? this.dueDay,
    limit: limit ?? this.limit,
    archived: archived ?? this.archived,
    inNetWorth: inNetWorth ?? this.inNetWorth,
    currency: currency,
  );
}

final class Category {
  const Category(
    this.name,
    this.icon,
    this.color, {
    this.income = false,
    this.parent,
    this.archived = false,
  });

  final String name;

  /// A key into the app's icon set, such as `food`.
  final String icon;
  final Color color;
  final bool income;

  /// The category this one sits under, if any.
  final String? parent;

  /// No longer offered for new entries; its history stays.
  final bool archived;

  Category copyWith({
    String? name,
    String? parent,
    bool clearParent = false,
    bool? archived,
  }) => Category(
    name ?? this.name,
    icon,
    color,
    income: income,
    parent: clearParent ? null : parent ?? this.parent,
    archived: archived ?? this.archived,
  );
}

/// One line of the book, in the smallest unit of its account's currency:
/// whole NT$ for most.
final class Entry {
  const Entry({
    required this.id,
    required this.date,
    required this.type,
    required this.amount,
    required this.account,
    this.category = '',
    this.note = '',
    this.to,
    this.holding,
    this.shares = 0,
    this.recurring,
    this.merchant = '',
    this.tags = const [],
    this.parts = const [],
    this.fee = 0,
    this.tax = 0,
    this.refundOf,
    this.installments = 0,
    this.average = false,
    this.split = false,
    this.home,
    this.received,
  });

  final String id;

  /// Midnight UTC of the day.
  final DateTime date;
  final EntryType type;
  final int amount;
  final String account;
  final String category;
  final String note;

  /// The receiving account of a transfer.
  final String? to;

  /// The stock code of an investment entry.
  final String? holding;
  final int shares;

  /// The recurring item this entry confirms.
  final String? recurring;

  /// Where the money went, such as 全聯福利中心; empty when not noted.
  final String merchant;

  /// Labels that cut across categories, such as 家用.
  final List<String> tags;

  /// A spending split across categories, each with its amount; empty when
  /// the whole goes to [category].
  final List<(String, int)> parts;

  /// The bank's fee on a transfer, the broker's on a trade.
  final int fee;

  /// The securities transaction tax on a sale.
  final int tax;

  /// The spending this income gives back, for a refund.
  final String? refundOf;

  /// How many monthly instalments a card purchase is paid in; 0 for one.
  final int installments;

  /// A sale costed at the average price rather than first in, first out.
  final bool average;

  /// A dividend entry whose [shares] come from a split rather than a stock
  /// dividend: the shares held multiply at the same cost.
  final bool split;

  /// For spending or income in a foreign-currency account: what it was
  /// worth in whole NT$ that day, which the reports and budgets count.
  final int? home;

  /// For a transfer between accounts in different currencies: what
  /// reached [to], in the smallest unit of its currency.
  final int? received;

  bool get isRefund => refundOf != null;

  /// [amount] in whole NT$: [home] when the entry has one.
  int get worth => home ?? amount;

  /// What reached [to] for a transfer.
  int get arrived => received ?? amount;

  /// What the entry adds to spending: an expense, a transfer's fee; a
  /// refund takes some back.
  int get spending => switch (type) {
    EntryType.expense => worth,
    EntryType.transfer => fee,
    EntryType.income when isRefund => -worth,
    _ => 0,
  };

  /// What the entry brings in: income and dividends, not refunds.
  int get earning => switch (type) {
    EntryType.income when !isRefund => worth,
    EntryType.dividend => amount,
    _ => 0,
  };

  /// [spending] by category: the parts of a split, a transfer's fee under
  /// [Ledger.feeCategory].
  List<(String, int)> get spendingParts {
    if (spending == 0) return const [];
    if (type == EntryType.transfer) return [(Ledger.feeCategory, fee)];
    if (parts.isNotEmpty && home == null) return parts;
    return [(category, spending)];
  }

  /// This entry under another [id], as the store knows it after an edit.
  Entry withId(String id) => Entry(
    id: id,
    date: date,
    type: type,
    amount: amount,
    account: account,
    category: category,
    note: note,
    to: to,
    holding: holding,
    shares: shares,
    recurring: recurring,
    merchant: merchant,
    tags: tags,
    parts: parts,
    fee: fee,
    tax: tax,
    refundOf: refundOf,
    installments: installments,
    average: average,
    split: split,
    home: home,
    received: received,
  );

  /// This entry with its merchant or tags changed.
  Entry withLabels({String? merchant, List<String>? tags}) => Entry(
    id: id,
    date: date,
    type: type,
    amount: amount,
    account: account,
    category: category,
    note: note,
    to: to,
    holding: holding,
    shares: shares,
    recurring: recurring,
    merchant: merchant ?? this.merchant,
    tags: tags ?? this.tags,
    parts: parts,
    fee: fee,
    tax: tax,
    refundOf: refundOf,
    installments: installments,
    average: average,
    split: split,
    home: home,
    received: received,
  );

  /// This entry with [from], or its category, renamed to [name].
  Entry withCategory(String name, {String? from}) => Entry(
    id: id,
    date: date,
    type: type,
    amount: amount,
    account: account,
    category: from == null || category == from ? name : category,
    note: note,
    to: to,
    holding: holding,
    shares: shares,
    recurring: recurring,
    merchant: merchant,
    tags: tags,
    parts: [
      for (final (part, value) in parts)
        (part == (from ?? category) ? name : part, value),
    ],
    fee: fee,
    tax: tax,
    refundOf: refundOf,
    installments: installments,
    average: average,
    split: split,
    home: home,
    received: received,
  );

  /// What the lists show: the note, else the category.
  String get title => note.isNotEmpty ? note : category;

  bool get isInvestment =>
      type == EntryType.buy ||
      type == EntryType.sell ||
      type == EntryType.dividend;
}

final class Holding {
  const Holding(
    this.code,
    this.name, {
    required this.shares,
    required this.price,
    required this.cost,
    required this.change,
    this.dividends = 0,
    this.realized = 0,
  });

  final String code;
  final String name;
  final int shares;

  /// The reference close, in NT$ with decimals.
  final double price;

  /// What the shares still held cost.
  final int cost;

  /// Today's change in market value.
  final int change;

  /// Dividends received so far.
  final int dividends;

  /// Profit or loss of shares already sold.
  final int realized;

  int get value => (shares * price).round();

  int get gain => value - cost;

  Holding copyWith({
    int? shares,
    double? price,
    int? cost,
    int? dividends,
    int? realized,
  }) => Holding(
    code,
    name,
    shares: shares ?? this.shares,
    price: price ?? this.price,
    cost: cost ?? this.cost,
    change: change,
    dividends: dividends ?? this.dividends,
    realized: realized ?? this.realized,
  );
}

/// Shares bought together and still held, with what they cost.
final class Lot {
  const Lot(this.date, this.shares, this.cost);

  final DateTime date;
  final int shares;
  final int cost;
}

final class Budget {
  const Budget(this.category, this.limit, {this.warning = 80});

  /// A category name, or [Ledger.allSpending] for the total.
  final String category;
  final int limit;

  /// The share used, in percent, at which the budget warns.
  final int warning;
}

/// How often a recurring item comes round.
enum RepeatUnit {
  day('天'),
  week('週'),
  month('個月'),
  year('年');

  const RepeatUnit(this.label);

  final String label;
}

final class Recurring {
  const Recurring({
    required this.id,
    required this.name,
    required this.amount,
    required this.day,
    required this.account,
    required this.category,
    this.active = true,
    this.unit = RepeatUnit.month,
    this.every = 1,
    this.start,
    this.end,
    this.income = false,
    this.merchant = '',
  });

  final String id;
  final String name;
  final int amount;

  /// Day of the month it falls due, for monthly items without [start].
  final int day;
  final String account;
  final String category;
  final bool active;
  final RepeatUnit unit;

  /// Every how many [unit]s.
  final int every;

  /// The first time it falls due; the weekday, day or date it keeps.
  final DateTime? start;

  /// The last day it may fall due, if it ends.
  final DateTime? end;

  /// Money coming in, such as a salary, rather than going out.
  final bool income;
  final String merchant;

  /// 「每月 5 日」「每 2 週 週五」「每年 3/15」.
  String get rhythm {
    final first = start;
    final n = every == 1 ? '' : ' $every ';
    final weekday = first == null ? '' : ' 週${_weekdays[first.weekday - 1]}';
    final date = first == null ? '' : ' ${first.month}/${first.day}';
    return switch (unit) {
      RepeatUnit.day => '每$n天',
      RepeatUnit.week => '每$n週$weekday',
      RepeatUnit.month =>
        '每$n${every == 1 ? '月' : '個月'} ${first?.day ?? day} 日',
      RepeatUnit.year => '每$n年$date',
    };
  }

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  Recurring copyWith({
    String? name,
    int? amount,
    String? account,
    String? category,
    bool? active,
  }) => Recurring(
    id: id,
    name: name ?? this.name,
    amount: amount ?? this.amount,
    day: day,
    account: account ?? this.account,
    category: category ?? this.category,
    active: active ?? this.active,
    unit: unit,
    every: every,
    start: start,
    end: end,
    income: income,
    merchant: merchant,
  );

  Recurring toggled() => copyWith(active: !active);

  /// The days in [year]/[month] it falls due.
  List<DateTime> datesIn(int year, int month) {
    final last = DateTime.utc(year, month + 1, 0);
    final first = start ?? DateTime.utc(2025, 1, day);
    final stop = end;
    bool keep(DateTime d) =>
        !d.isBefore(first) && (stop == null || !d.isAfter(stop));
    final dates = <DateTime>[];
    switch (unit) {
      case RepeatUnit.day || RepeatUnit.week:
        final step = every * (unit == RepeatUnit.week ? 7 : 1);
        final monthStart = DateTime.utc(year, month);
        final gap = monthStart.difference(first).inDays;
        var d = gap <= 0
            ? first
            : first.add(Duration(days: (gap + step - 1) ~/ step * step));
        while (!d.isAfter(last)) {
          if (keep(d)) dates.add(d);
          d = d.add(Duration(days: step));
        }
      case RepeatUnit.month:
        final months = (year - first.year) * 12 + month - first.month;
        if (months >= 0 && months % every == 0) {
          final d = DateTime.utc(year, month, min(first.day, last.day));
          if (keep(d)) dates.add(d);
        }
      case RepeatUnit.year:
        final years = year - first.year;
        if (month == first.month && years >= 0 && years % every == 0) {
          final d = DateTime.utc(year, month, min(first.day, last.day));
          if (keep(d)) dates.add(d);
        }
    }
    return dates;
  }
}

/// The screens' book: accounts, categories, entries, holdings, budgets
/// and recurring items, with the sums the screens show. Holdings are
/// replayed from the starting positions and the investment entries, so
/// edits and deletions always recompute them.
final class Ledger extends ChangeNotifier {
  Ledger({
    required this.today,
    required List<Account> accounts,
    required List<Category> categories,
    required List<Entry> entries,
    required List<Holding> holdings,
    required List<Budget> budgets,
    required List<Recurring> recurring,
    this.journal,
    Map<String, double> rates = const {},
  }) : _rates = {...rates},
       _accounts = [...accounts],
       _categories = [...categories],
       _entries = [...entries],
       _startHoldings = [...holdings],
       _budgets = [...budgets],
       _recurring = [...recurring] {
    _replay();
  }

  static const allSpending = '全部支出';

  /// Where transfer fees are counted.
  static const feeCategory = '其他支出';

  final DateTime today;

  /// Where changes are kept; none in the preview, which forgets them.
  final Journal? journal;

  /// The last change the [journal] refused, for the screens to report.
  final problem = ValueNotifier<Object?>(null);

  final List<Account> _accounts;
  final List<Category> _categories;
  final List<Entry> _entries;
  final List<Holding> _startHoldings;
  final List<Budget> _budgets;
  final List<Recurring> _recurring;
  final Map<String, double> _rates;
  var _holdings = <Holding>[];
  var _lots = <String, List<Lot>>{};

  /// Hides the summary figures on the overview and accounts.
  var hidden = false;

  List<Account> get accounts => List.unmodifiable(_accounts);
  List<Category> get categories => List.unmodifiable(_categories);
  List<Holding> get holdings => List.unmodifiable(_holdings);
  List<Budget> get budgets => List.unmodifiable(_budgets);
  List<Recurring> get recurring => List.unmodifiable(_recurring);

  /// Categories offered for new entries: open ones of the kind.
  List<Category> categoriesFor({required bool income}) => [
    for (final c in _categories)
      if (c.income == income && !c.archived) c,
  ];

  Account account(String id) {
    final accounts = _accountIndex ??= {for (final a in _accounts) a.id: a};
    return accounts[id] ?? Account(id, id, AccountKind.bank, 0);
  }

  Category category(String name) => _categories.firstWhere(
    (c) => c.name == name,
    orElse: () => Category(name, 'other', const Color(0xFF8C8C80)),
  );

  /// The lots of [code] still held, oldest first.
  List<Lot> lotsOf(String code) => List.unmodifiable(_lots[code] ?? const []);

  /// What selling [shares] of [code] now would cost: the oldest lots
  /// first, or the average price.
  int saleCost(String code, int shares, {bool average = false}) =>
      _take(_lots[code] ?? const [], shares, average: average).$1;

  /// The cost of selling [shares] out of [lots], and the lots left.
  static (int, List<Lot>) _take(
    List<Lot> lots,
    int shares, {
    required bool average,
  }) {
    final held = lots.fold(0, (sum, l) => sum + l.shares);
    if (shares > held) throw StateError('賣出股數超過持有股數');
    if (average) {
      final cost = lots.fold(0, (sum, l) => sum + l.cost);
      final part = held == 0 ? 0 : (cost * shares / held).round();
      final left = held - shares;
      return (
        part,
        left == 0 ? <Lot>[] : [Lot(lots.last.date, left, cost - part)],
      );
    }
    var need = shares;
    var part = 0;
    final rest = <Lot>[];
    for (final lot in lots) {
      if (need == 0) {
        rest.add(lot);
      } else if (lot.shares <= need) {
        part += lot.cost;
        need -= lot.shares;
      } else {
        final piece = (lot.cost * need / lot.shares).round();
        part += piece;
        rest.add(Lot(lot.date, lot.shares - need, lot.cost - piece));
        need = 0;
      }
    }
    return (part, rest);
  }

  Holding? holding(String code) {
    for (final h in _holdings) {
      if (h.code == code) return h;
    }
    return null;
  }

  // Entries.

  /// Entries in [year]/[month], newest day first; within a day the most
  /// recently recorded first.
  List<Entry> entriesIn(int year, int month) {
    final months = _months ??= _indexMonths();
    return List.of(months[year * 12 + month] ?? const <Entry>[]);
  }

  /// Every month's entries in [entriesIn] order, built once per change.
  Map<int, List<Entry>> _indexMonths() {
    final groups = <int, List<(int, Entry)>>{};
    for (final (i, e) in _entries.indexed) {
      (groups[e.date.year * 12 + e.date.month] ??= []).add((i, e));
    }
    final months = <int, List<Entry>>{};
    for (final MapEntry(key: month, value: found) in groups.entries) {
      found.sort((a, b) {
        final byDate = b.$2.date.compareTo(a.$2.date);
        return byDate != 0 ? byDate : b.$1.compareTo(a.$1);
      });
      months[month] = [for (final (_, e) in found) e];
    }
    return months;
  }

  /// What the screens ask for again and again, worked out once per change:
  /// entries by month, balances by account and day, accounts by id.
  Map<int, List<Entry>>? _months;
  final _balances = <(String, DateTime), int>{};
  Map<String, Account>? _accountIndex;

  void _touch() {
    _months = null;
    _balances.clear();
    _accountIndex = null;
  }

  @override
  void notifyListeners() {
    _touch();
    super.notifyListeners();
  }

  List<Entry> entriesOn(DateTime day) => [
    for (final e in entriesIn(day.year, day.month))
      if (e.date == day) e,
  ];

  int _sum(Iterable<Entry> entries) =>
      entries.fold(0, (total, e) => total + e.amount);

  /// Income of a month, dividends included.
  int income(int year, int month) =>
      entriesIn(year, month).fold(0, (total, e) => total + e.earning);

  /// Spending of a month, less refunds, with transfer fees.
  int expense(int year, int month, {int? untilDay}) => entriesIn(year, month)
      .where((e) => untilDay == null || e.date.day <= untilDay)
      .fold(0, (total, e) => total + e.spending);

  int dividends(int year, int month) =>
      _sum(entriesIn(year, month).where((e) => e.type == EntryType.dividend));

  int spentOn(DateTime day) =>
      entriesOn(day).fold(0, (total, e) => total + e.spending);

  /// A month's spending by category, largest first.
  List<(Category, int)> expenseByCategory(
    int year,
    int month, {
    int? untilDay,
  }) {
    final totals = <String, int>{};
    for (final e in entriesIn(year, month)) {
      if (untilDay != null && e.date.day > untilDay) continue;
      for (final (name, value) in e.spendingParts) {
        totals[name] = (totals[name] ?? 0) + value;
      }
    }
    final rows = [
      for (final MapEntry(:key, :value) in totals.entries)
        (category(key), value),
    ];
    rows.sort((a, b) => b.$2.compareTo(a.$2));
    return rows;
  }

  // Any stretch of days, for the reports.

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
      _sum(_between(from, to).where((e) => e.type == EntryType.dividend));

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
  DateTime get firstDay => _entries.isEmpty
      ? today
      : _entries.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);

  // Balances.

  /// What [e] does to [account] by the end of [at].
  int _effect(Entry e, String account, DateTime at) {
    var change = 0;
    if (e.account == account) {
      change += switch (e.type) {
        EntryType.income || EntryType.dividend => e.amount,
        EntryType.sell => e.amount - e.fee - e.tax,
        EntryType.buy || EntryType.transfer => -(e.amount + e.fee),
        EntryType.expense => -billed(e, at),
      };
    }
    if (e.type == EntryType.transfer && e.to == account) change += e.arrived;
    return change;
  }

  // Cards.

  /// The last statement closing of [card] on or before [day].
  DateTime closingOn(Account card, DateTime day) {
    DateTime closing(int year, int month) => DateTime.utc(
      year,
      month,
      min(card.closingDay ?? 1, DateTime.utc(year, month + 1, 0).day),
    );
    final here = closing(day.year, day.month);
    return here.isAfter(day) ? closing(day.year, day.month - 1) : here;
  }

  /// How much of [e] has reached its card's statements by [at]: all of
  /// it, or the instalments billed so far.
  int billed(Entry e, DateTime at) {
    final count = e.installments;
    if (count < 2) return e.amount;
    final periods = billedPeriods(e, at);
    if (periods == 0) return 0;
    // Equal parts rounded down, the remainder in the first one, as card
    // issuers bill it and as the ledger's own schedule has it.
    final each = e.amount ~/ count;
    return periods >= count ? e.amount : e.amount - each * (count - periods);
  }

  /// How many instalments of [e] have been billed by [at].
  int billedPeriods(Entry e, DateTime at) {
    final card = account(e.account);
    var periods = 0;
    var month = DateTime.utc(e.date.year, e.date.month);
    while (!month.isAfter(at) && periods < e.installments) {
      final closing = closingOn(card, _lastDayOf(month));
      if (closing.isAfter(e.date) && !closing.isAfter(at)) periods++;
      month = DateTime.utc(month.year, month.month + 1);
    }
    return periods;
  }

  static DateTime _lastDayOf(DateTime month) =>
      DateTime.utc(month.year, month.month + 1, 0);

  /// The last closed statement of [card]: its first and last day and when
  /// it must be paid.
  (DateTime, DateTime, DateTime) statement(Account card) {
    final end = closingOn(card, today);
    final start = closingOn(
      card,
      end.subtract(const Duration(days: 1)),
    ).add(const Duration(days: 1));
    final day = card.dueDay ?? 15;
    var due = DateTime.utc(end.year, end.month, day);
    if (!due.isAfter(end)) due = DateTime.utc(end.year, end.month + 1, day);
    return (start, end, due);
  }

  /// What is still to pay on the last statement of [card].
  int statementDue(Account card) {
    final (_, end, _) = statement(card);
    var paid = 0;
    for (final e in _entries) {
      if (e.type == EntryType.transfer &&
          e.to == card.id &&
          e.date.isAfter(end)) {
        paid += e.arrived;
      }
    }
    return max(0, -balance(card.id, until: end) - paid);
  }

  /// Purchases on [card] since its last statement closed.
  List<Entry> unbilled(Account card) {
    final (_, end, _) = statement(card);
    return [
      for (final e in _entries)
        if (e.account == card.id &&
            e.type == EntryType.expense &&
            e.installments < 2 &&
            e.date.isAfter(end))
          e,
    ]..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Purchases on [card] still being paid in instalments.
  List<Entry> instalmentsOn(Account card) => [
    for (final e in _entries)
      if (e.account == card.id &&
          e.installments > 1 &&
          billedPeriods(e, today) < e.installments)
        e,
  ];

  /// Known merchants, most used first.
  List<String> get merchants {
    final counts = <String, int>{};
    for (final e in _entries) {
      if (e.merchant.isEmpty) continue;
      counts[e.merchant] = (counts[e.merchant] ?? 0) + 1;
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  /// The category last used with [merchant], if any.
  String? categoryAt(String merchant) {
    Entry? latest;
    for (final e in _entries) {
      if (e.merchant != merchant || e.type != EntryType.expense) continue;
      if (latest == null || e.date.isAfter(latest.date)) latest = e;
    }
    return latest?.category;
  }

  /// Every tag with how many entries carry it and their spending, most
  /// used first.
  List<(String, int, int)> get tagStats {
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
  List<String> get tags {
    final counts = <String, int>{};
    for (final e in _entries) {
      for (final tag in e.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  /// Every trade and dividend of [code], newest first.
  List<Entry> tradesOf(String code) => [
    for (final e in _entries)
      if (e.holding == code) e,
  ]..sort((a, b) => b.date.compareTo(a.date));

  /// The entry with [id], if it is still in the book.
  Entry? byId(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// How much of [original] is left to refund.
  int refundable(Entry original) {
    var back = 0;
    for (final e in _entries) {
      if (e.refundOf == original.id) back += e.amount;
    }
    return original.amount - back;
  }

  /// The balance of [account] at the end of [until], or of today.
  int balance(String account, {DateTime? until}) {
    final end = until ?? today;
    return _balances[(account, end)] ??= _balanceOn(account, end);
  }

  int _balanceOn(String account, DateTime end) {
    var total = this.account(account).opening;
    for (final e in _entries) {
      if (!e.date.isAfter(end)) total += _effect(e, account, end);
    }
    return total;
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

  // Currencies.

  /// NT$ for one unit of each foreign currency: 臺灣銀行's spot buying
  /// rate, what a foreign balance would fetch today. Empty until fetched.
  Map<String, double> get rates => Map.unmodifiable(_rates);

  /// [minor] units of [currency] in whole NT$ at [rates]; null without a
  /// rate for it.
  int? toHome(int minor, String currency) {
    if (currency == 'TWD') return minor;
    final rate = _rates[currency];
    if (rate == null) return null;
    return (minor / _unit(currency) * rate).round();
  }

  /// [amount] of [from] in the smallest unit of [to], through NT$ at
  /// [rates]; null without a rate for either.
  int? convert(int amount, String from, String to) {
    if (from == to) return amount;
    final home = from == 'TWD' ? amount.toDouble() : _rated(amount, from);
    if (home == null) return null;
    if (to == 'TWD') return home.round();
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

  /// Counted accounts less debts plus investments at today's value, at
  /// the end of [day].
  int netWorthAt(DateTime day) {
    var total = investValue;
    for (final a in _accounts) {
      if (a.inNetWorth) total += worthOf(a, until: day);
    }
    return total;
  }

  /// The change of [account] in each of the [weeks] calendar weeks
  /// ending with this one, oldest first, with each week's Monday.
  List<(DateTime, int)> weeklyChanges(String account, {int weeks = 4}) {
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

  // Budgets and recurring items.

  Budget budgetFor(String category) => _budgets.firstWhere(
    (b) => b.category == category,
    orElse: () => Budget(category, 0),
  );

  /// The entry confirming [item] in [year]/[month], if any.
  Entry? confirmation(Recurring item, int year, int month) {
    for (final e in entriesIn(year, month)) {
      if (e.recurring == item.id) return e;
    }
    return null;
  }

  /// The entries booking [item] in [year]/[month], earliest first.
  List<Entry> confirmationsIn(Recurring item, int year, int month) => [
    for (final e in entriesIn(year, month).reversed)
      if (e.recurring == item.id) e,
  ];

  /// The first day of this month [item] falls due and is not yet booked:
  /// bookings count against its days in order, so one booked early still
  /// settles that day.
  DateTime? pendingDate(Recurring item) {
    if (!item.active) return null;
    final dates = item.datesIn(today.year, today.month);
    final booked = confirmationsIn(item, today.year, today.month).length;
    return booked < dates.length ? dates[booked] : null;
  }

  /// The next day [item] falls due, this month or later.
  DateTime? nextDate(Recurring item) {
    final pending = pendingDate(item);
    if (pending != null) return pending;
    for (var k = 1; k <= 24; k++) {
      final month = DateTime.utc(today.year, today.month + k);
      final dates = item.datesIn(month.year, month.month);
      if (dates.isNotEmpty) return dates.first;
    }
    return null;
  }

  /// [nextDate] as 「10/5」.
  String nextLabel(Recurring item) {
    final d = nextDate(item);
    return d == null ? '' : '${d.month}/${d.day}';
  }

  /// Active items whose day has come this month but are not yet booked.
  List<Recurring> get due => [
    for (final r in _recurring)
      if (pendingDate(r) case final d? when !d.isAfter(today)) r,
  ];

  /// Active items still to come this month, soonest first.
  List<Recurring> get upcoming {
    final rows = [
      for (final r in _recurring)
        if (pendingDate(r) case final d? when d.isAfter(today)) (r, d),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final (r, _) in rows) r];
  }

  // Changes.

  String newId() => PublicId.generate().value;

  var _queue = Future<void>.value();
  var _waiting = 0;

  /// The id an edited entry has in the [journal] now, by its old one.
  final _renamed = <String, String>{};

  String _current(String id) {
    var current = id;
    for (var hops = 0; hops < 64; hops++) {
      final next = _renamed[current];
      if (next == null) break;
      current = next;
    }
    return current;
  }

  /// Done once every change so far has reached the [journal] and the
  /// ledger has reloaded what it kept.
  Future<void> get settled => _queue;

  /// Passes a change to the [journal]. Once nothing else waits, reloads
  /// what was kept, so ids and figures match the store; a refused change
  /// is undone that way and reported through [problem].
  void _keep(Future<void> Function(Journal journal) change) {
    final journal = this.journal;
    if (journal == null) return;
    _waiting++;
    _queue = _queue.then((_) async {
      try {
        await change(journal);
      } on Object catch (error) {
        problem.value = error;
      }
      if (--_waiting > 0) return;
      try {
        final fresh = await journal.load();
        // A change made while loading is newer than what was loaded; the
        // load after it brings both.
        if (_waiting == 0) _adopt(fresh);
      } on Object catch (error) {
        problem.value = error;
      }
    });
  }

  /// Reloads what the [journal] keeps, such as new closing prices.
  void refresh() => _keep((_) async {});

  /// Adds [entry]; a sale of more shares than are held is refused.
  void add(Entry entry) {
    _entries.add(entry);
    _replayOrUndo(() => _entries.removeLast());
    _keep((j) => j.addEntries([entry]));
  }

  /// Adds every one of [entries] at once, as an import does.
  void addAll(List<Entry> entries) {
    if (entries.isEmpty) return;
    final count = _entries.length;
    _entries.addAll(entries);
    _replayOrUndo(() => _entries.removeRange(count, _entries.length));
    _keep((j) => j.addEntries(entries));
  }

  /// Puts [entry] in place of the entry with the same id.
  void replace(Entry entry) {
    final id = _current(entry.id);
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return add(entry);
    final before = _entries[index];
    _entries[index] = entry;
    _replayOrUndo(() => _entries[index] = before);
    // The id is looked up when the change runs: an edit queued before it
    // may have given the entry a new one.
    _keep((j) async {
      final stored = _current(before.id);
      final next = await j.replaceEntry(before.withId(stored), entry);
      if (next != stored) _renamed[stored] = next;
    });
  }

  /// Removes the entry with [id] and returns it with its place, for undo.
  (int, Entry)? remove(String id) {
    final current = _current(id);
    final index = _entries.indexWhere((e) => e.id == current);
    if (index < 0) return null;
    final removed = _entries.removeAt(index);
    _replayOrUndo(() => _entries.insert(index, removed));
    _keep((j) => j.removeEntry(removed.withId(_current(removed.id))));
    return (index, removed);
  }

  void restore((int, Entry) removed) {
    final (index, entry) = removed;
    _entries.insert(index.clamp(0, _entries.length), entry);
    _replayOrUndo(() => _entries.remove(entry));
    _keep((j) => j.addEntries([entry]));
  }

  void setBudget(String category, int limit, {int? warning}) {
    final old = budgetFor(category);
    _budgets.removeWhere((b) => b.category == category);
    final budget = Budget(category, limit, warning: warning ?? old.warning);
    _budgets.add(budget);
    notifyListeners();
    _keep((j) => j.setBudget(budget));
  }

  void removeBudget(String category) {
    _budgets.removeWhere((b) => b.category == category);
    notifyListeners();
    _keep((j) => j.removeBudget(category));
  }

  void addAccount(Account account) {
    _accounts.add(account);
    notifyListeners();
    _keep((j) => j.saveAccount(null, account));
  }

  /// Puts [account] in place of the one with the same id.
  void updateAccount(Account account) {
    final index = _accounts.indexWhere((a) => a.id == account.id);
    if (index < 0) return addAccount(account);
    final before = _accounts[index];
    _accounts[index] = account;
    notifyListeners();
    _keep((j) => j.saveAccount(before, account));
  }

  /// Corrects [id]'s balance today to [target] by moving its opening
  /// balance, so its history keeps its shape.
  void setBalance(String id, int target) {
    final index = _accounts.indexWhere((a) => a.id == id);
    if (index < 0) return;
    final a = _accounts[index];
    final moved = a.copyWith(opening: a.opening + target - balance(id));
    _accounts[index] = moved;
    notifyListeners();
    _keep((j) => j.setOpening(moved, moved.opening));
  }

  /// Whether [id] has any entries; an account without can be removed.
  bool isUsed(String id) => _entries.any((e) => e.account == id || e.to == id);

  void removeAccount(String id) {
    if (isUsed(id)) return;
    final index = _accounts.indexWhere((a) => a.id == id);
    if (index < 0) return;
    final removed = _accounts.removeAt(index);
    notifyListeners();
    _keep((j) => j.removeAccount(removed));
  }

  void addCategory(Category category) {
    _categories.add(category);
    notifyListeners();
    _keep((j) => j.saveCategory(null, category));
  }

  /// Changes a category's name, mark and colour; a new name reaches every
  /// entry, budget and recurring item that uses it.
  void editCategory(String from, Category next) => updateCategory(from, next);

  /// Renames a category and every entry, budget and recurring item that
  /// uses it.
  void renameCategory(String from, String to) {
    final index = _categories.indexWhere((c) => c.name == from);
    if (index < 0 || from == to || to.isEmpty) return;
    updateCategory(from, _categories[index].copyWith(name: to));
  }

  void _renameCategory(String from, String to) {
    if (from == to || to.isEmpty) return;
    for (final (i, c) in _categories.indexed) {
      if (c.name == from) _categories[i] = c.copyWith(name: to);
      if (c.parent == from) _categories[i] = c.copyWith(parent: to);
    }
    for (final (i, e) in _entries.indexed) {
      if (e.category == from) _entries[i] = e.withCategory(to);
    }
    for (final (i, b) in _budgets.indexed) {
      if (b.category == from) _budgets[i] = Budget(to, b.limit);
    }
    for (final (i, r) in _recurring.indexed) {
      if (r.category == from) _recurring[i] = r.copyWith(category: to);
    }
    notifyListeners();
  }

  void toggleRecurring(String id) {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index < 0) return;
    final toggled = _recurring[index].toggled();
    _recurring[index] = toggled;
    notifyListeners();
    _keep((j) => j.saveRecurring(toggled));
  }

  /// The entry that books [item] on its pending day, or today if that is
  /// later, for the composer to show before it is saved.
  Entry booking(Recurring item) {
    final date = pendingDate(item) ?? today;
    return Entry(
      id: '',
      date: date.isAfter(today) ? today : date,
      type: item.income ? EntryType.income : EntryType.expense,
      amount: item.amount,
      account: item.account,
      category: item.category,
      note: item.name,
      recurring: item.id,
      merchant: item.merchant,
    );
  }

  /// Books [item] as it stands.
  void confirm(Recurring item) {
    final entry = booking(item);
    add(
      Entry(
        id: newId(),
        date: entry.date,
        type: entry.type,
        amount: entry.amount,
        account: entry.account,
        category: entry.category,
        note: entry.note,
        recurring: entry.recurring,
        merchant: entry.merchant,
      ),
    );
  }

  /// Puts [item] in place of the one with the same id, or adds it.
  void saveRecurring(Recurring item) {
    final index = _recurring.indexWhere((r) => r.id == item.id);
    if (index < 0) {
      _recurring.add(item);
    } else {
      _recurring[index] = item;
    }
    notifyListeners();
    _keep((j) => j.saveRecurring(item));
  }

  void removeRecurring(String id) {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index < 0) return;
    final removed = _recurring.removeAt(index);
    notifyListeners();
    _keep((j) => j.removeRecurring(removed));
  }

  /// Changes a category's place, name, mark, colour or archive state; a
  /// new name reaches every entry, budget and recurring item that uses it.
  void updateCategory(String name, Category next) {
    final index = _categories.indexWhere((c) => c.name == name);
    if (index < 0) return;
    final before = _categories[index];
    if (next.name != name) _renameCategory(name, next.name);
    _categories[index] = next;
    notifyListeners();
    _keep((j) => j.saveCategory(before, next));
  }

  /// Moves everything in [from] to [into] and removes [from].
  void mergeCategory(String from, String into) {
    if (from == into) return;
    final source = category(from);
    final target = category(into);
    for (final (i, e) in _entries.indexed) {
      if (e.category == from || e.parts.any((p) => p.$1 == from)) {
        _entries[i] = e.withCategory(into, from: from);
      }
    }
    for (final (i, r) in _recurring.indexed) {
      if (r.category == from) _recurring[i] = r.copyWith(category: into);
    }
    _budgets.removeWhere((b) => b.category == from);
    _categories.removeWhere((c) => c.name == from);
    for (final (i, c) in _categories.indexed) {
      if (c.parent == from) _categories[i] = c.copyWith(clearParent: true);
    }
    notifyListeners();
    _keep((j) => j.mergeCategory(source, target));
  }

  /// Renames or merges a tag across every entry; an empty [to] removes it.
  void renameTag(String from, String to) {
    for (final (i, e) in _entries.indexed) {
      if (!e.tags.contains(from)) continue;
      final tags = {
        for (final t in e.tags)
          if (t != from) t,
        if (to.isNotEmpty) to,
      }.toList();
      _entries[i] = e.withLabels(tags: tags);
    }
    notifyListeners();
    _keep((j) => j.relabel(from, to, merchant: false));
  }

  /// Renames or merges a merchant across every entry; an empty [to]
  /// clears it.
  void renameMerchant(String from, String to) {
    for (final (i, e) in _entries.indexed) {
      if (e.merchant == from) _entries[i] = e.withLabels(merchant: to);
    }
    notifyListeners();
    _keep((j) => j.relabel(from, to, merchant: true));
  }

  /// Replaces everything with the contents of [fresh], for a demo reset.
  void resetTo(Ledger fresh) {
    _adopt(fresh);
    hidden = false;
    amountsHidden = false;
    notifyListeners();
  }

  /// Takes the contents of [fresh], as reloaded from the [journal].
  void _adopt(Ledger fresh) {
    _accounts
      ..clear()
      ..addAll(fresh._accounts);
    _categories
      ..clear()
      ..addAll(fresh._categories);
    _entries
      ..clear()
      ..addAll(fresh._entries);
    _startHoldings
      ..clear()
      ..addAll(fresh._startHoldings);
    _budgets
      ..clear()
      ..addAll(fresh._budgets);
    _recurring
      ..clear()
      ..addAll(fresh._recurring);
    _rates
      ..clear()
      ..addAll(fresh._rates);
    _replay();
    notifyListeners();
  }

  void addRecurring(Recurring item) {
    _recurring.add(item);
    notifyListeners();
    _keep((j) => j.saveRecurring(item));
  }

  void toggleHidden() {
    hidden = !hidden;
    amountsHidden = hidden;
    notifyListeners();
  }

  void _replayOrUndo(void Function() undo) {
    try {
      _replay();
    } on StateError {
      undo();
      _replay();
      rethrow;
    }
    notifyListeners();
  }

  /// [lots] with their shares grown to [total] in proportion, each at its
  /// own cost; the last takes what rounding leaves.
  static List<Lot> _scaled(List<Lot> lots, int total) {
    final held = lots.fold(0, (sum, l) => sum + l.shares);
    if (held == 0) return lots;
    var left = total;
    final scaled = <Lot>[];
    for (final (i, l) in lots.indexed) {
      final last = i == lots.length - 1;
      final shares = last ? left : (l.shares * total / held).round();
      left -= shares;
      scaled.add(Lot(l.date, shares, l.cost));
    }
    return scaled;
  }

  /// Rebuilds the holdings and their lots from the starting positions and
  /// every investment entry in date order.
  void _replay() {
    _touch();
    final opening = DateTime.utc(2025);
    final byCode = {for (final h in _startHoldings) h.code: h};
    final lots = <String, List<Lot>>{
      for (final h in _startHoldings)
        h.code: [if (h.shares > 0) Lot(opening, h.shares, h.cost)],
    };
    final trades = [
      for (final e in _entries)
        if (e.isInvestment && e.holding != null) e,
    ]..sort((a, b) => a.date.compareTo(b.date));
    for (final e in trades) {
      final code = e.holding!;
      // A stock bought for the first time takes its first price per share
      // as the reference until a close is known.
      final held =
          byCode[code] ??
          Holding(
            code,
            code,
            shares: 0,
            price: e.shares == 0 ? 0 : e.amount / e.shares,
            cost: 0,
            change: 0,
          );
      switch (e.type) {
        case EntryType.buy:
          final cost = e.amount + e.fee;
          lots[code] = [...?lots[code], Lot(e.date, e.shares, cost)];
          byCode[code] = held.copyWith(
            shares: held.shares + e.shares,
            cost: held.cost + cost,
          );
        case EntryType.sell:
          final (part, rest) = _take(
            lots[code] ?? const [],
            e.shares,
            average: e.average,
          );
          lots[code] = rest;
          byCode[code] = held.copyWith(
            shares: held.shares - e.shares,
            cost: held.cost - part,
            realized: held.realized + e.amount - e.fee - e.tax - part,
          );
        case EntryType.dividend when e.split && held.shares > 0:
          final ratio = (held.shares + e.shares) / held.shares;
          lots[code] = _scaled(lots[code] ?? const [], held.shares + e.shares);
          byCode[code] = held.copyWith(
            shares: held.shares + e.shares,
            price: held.price / ratio,
            dividends: held.dividends + e.amount,
          );
        case EntryType.dividend:
          if (e.shares > 0) {
            lots[code] = [...?lots[code], Lot(e.date, e.shares, 0)];
          }
          byCode[code] = held.copyWith(
            shares: held.shares + e.shares,
            dividends: held.dividends + e.amount,
          );
        default:
          break;
      }
    }
    _lots = lots;
    _holdings = [
      for (final h in byCode.values)
        if (h.shares > 0 || h.realized != 0) h,
    ]..sort((a, b) => b.value.compareTo(a.value));
  }
}
