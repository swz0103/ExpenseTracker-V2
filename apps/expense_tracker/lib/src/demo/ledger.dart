import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import '../look/figures.dart';

/// What an entry does. Buys, sells and dividends are investment entries.
enum EntryType { expense, income, transfer, buy, sell, dividend }

enum AccountKind { cash, bank, wallet, card }

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
  });

  final String id;
  final String name;
  final AccountKind kind;

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
}

final class Category {
  const Category(this.name, this.icon, this.color, {this.income = false});

  final String name;

  /// A key into the app's icon set, such as `food`.
  final String icon;
  final Color color;
  final bool income;
}

/// One line of the book, in whole NT$.
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

  bool get isRefund => refundOf != null;

  /// What the entry adds to spending: an expense, a transfer's fee; a
  /// refund takes some back.
  int get spending => switch (type) {
    EntryType.expense => amount,
    EntryType.transfer => fee,
    EntryType.income when isRefund => -amount,
    _ => 0,
  };

  /// What the entry brings in: income and dividends, not refunds.
  int get earning => switch (type) {
    EntryType.income when !isRefund => amount,
    EntryType.dividend => amount,
    _ => 0,
  };

  /// [spending] by category: the parts of a split, a transfer's fee under
  /// [Ledger.feeCategory].
  List<(String, int)> get spendingParts {
    if (spending == 0) return const [];
    if (type == EntryType.transfer) return [(Ledger.feeCategory, fee)];
    if (parts.isNotEmpty) return parts;
    return [(category, spending)];
  }

  /// This entry with another category.
  Entry withCategory(String name) => Entry(
    id: id,
    date: date,
    type: type,
    amount: amount,
    account: account,
    category: name,
    note: note,
    to: to,
    holding: holding,
    shares: shares,
    recurring: recurring,
    merchant: merchant,
    tags: tags,
    parts: [
      for (final (part, value) in parts)
        (part == category ? name : part, value),
    ],
    fee: fee,
    tax: tax,
    refundOf: refundOf,
    installments: installments,
    average: average,
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

  Holding copyWith({int? shares, int? cost, int? dividends, int? realized}) =>
      Holding(
        code,
        name,
        shares: shares ?? this.shares,
        price: price,
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
  const Budget(this.category, this.limit);

  /// A category name, or [Ledger.allSpending] for the total.
  final String category;
  final int limit;
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
  });

  final String id;
  final String name;
  final int amount;

  /// Day of the month it falls due.
  final int day;
  final String account;
  final String category;
  final bool active;

  Recurring toggled() => Recurring(
    id: id,
    name: name,
    amount: amount,
    day: day,
    account: account,
    category: category,
    active: !active,
  );
}

/// The preview's book: accounts, categories, entries, holdings, budgets
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
  }) : _accounts = [...accounts],
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
  final List<Account> _accounts;
  final List<Category> _categories;
  final List<Entry> _entries;
  final List<Holding> _startHoldings;
  final List<Budget> _budgets;
  final List<Recurring> _recurring;
  var _holdings = <Holding>[];
  var _lots = <String, List<Lot>>{};
  var _serial = 0;

  /// Hides the summary figures on the overview and accounts.
  var hidden = false;

  List<Account> get accounts => List.unmodifiable(_accounts);
  List<Category> get categories => List.unmodifiable(_categories);
  List<Holding> get holdings => List.unmodifiable(_holdings);
  List<Budget> get budgets => List.unmodifiable(_budgets);
  List<Recurring> get recurring => List.unmodifiable(_recurring);

  List<Category> categoriesFor({required bool income}) => [
    for (final c in _categories)
      if (c.income == income) c,
  ];

  Account account(String id) => _accounts.firstWhere(
    (a) => a.id == id,
    orElse: () => Account(id, id, AccountKind.bank, 0),
  );

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
    final found = [
      for (final (i, e) in _entries.indexed)
        if (e.date.year == year && e.date.month == month) (i, e),
    ];
    found.sort((a, b) {
      final byDate = b.$2.date.compareTo(a.$2.date);
      return byDate != 0 ? byDate : b.$1.compareTo(a.$1);
    });
    return [for (final (_, e) in found) e];
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
    if (e.type == EntryType.transfer && e.to == account) change += e.amount;
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
    final each = e.amount ~/ count;
    return periods >= count ? e.amount : each * periods;
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
        paid += e.amount;
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

  /// Cash in every account but cards, plus investments.
  int get assets {
    var total = investValue;
    for (final a in _accounts) {
      if (a.kind != AccountKind.card) total += balance(a.id);
    }
    return total;
  }

  /// What is owed on cards, as a positive amount.
  int get cardDebt {
    var total = 0;
    for (final a in _accounts) {
      if (a.kind == AccountKind.card) total += -balance(a.id);
    }
    return total < 0 ? 0 : total;
  }

  /// Accounts less card debt plus investments at today's value, at the
  /// end of [day].
  int netWorthAt(DateTime day) {
    var total = investValue;
    for (final a in _accounts) {
      total += balance(a.id, until: day);
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

  /// Active items not yet confirmed this month whose day has come.
  List<Recurring> get due => [
    for (final r in _recurring)
      if (r.active &&
          r.day <= today.day &&
          confirmation(r, today.year, today.month) == null)
        r,
  ];

  /// Active items not yet confirmed this month, still to come.
  List<Recurring> get upcoming => [
    for (final r in _recurring)
      if (r.active &&
          r.day > today.day &&
          confirmation(r, today.year, today.month) == null)
        r,
  ]..sort((a, b) => a.day.compareTo(b.day));

  // Changes.

  String newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return 'entry-$stamp-${_serial++}';
  }

  /// Adds [entry]; a sale of more shares than are held is refused.
  void add(Entry entry) {
    _entries.add(entry);
    _replayOrUndo(() => _entries.removeLast());
  }

  /// Puts [entry] in place of the entry with the same id.
  void replace(Entry entry) {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index < 0) return add(entry);
    final before = _entries[index];
    _entries[index] = entry;
    _replayOrUndo(() => _entries[index] = before);
  }

  /// Removes the entry with [id] and returns it with its place, for undo.
  (int, Entry)? remove(String id) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return null;
    final removed = _entries.removeAt(index);
    _replayOrUndo(() => _entries.insert(index, removed));
    return (index, removed);
  }

  void restore((int, Entry) removed) {
    final (index, entry) = removed;
    _entries.insert(index.clamp(0, _entries.length), entry);
    _replayOrUndo(() => _entries.remove(entry));
  }

  void setBudget(String category, int limit) {
    _budgets.removeWhere((b) => b.category == category);
    _budgets.add(Budget(category, limit));
    notifyListeners();
  }

  void addAccount(Account account) {
    _accounts.add(account);
    notifyListeners();
  }

  void addCategory(Category category) {
    _categories.add(category);
    notifyListeners();
  }

  /// Changes a category's name, mark and colour; a new name reaches every
  /// entry, budget and recurring item that uses it.
  void editCategory(String from, Category next) {
    renameCategory(from, next.name);
    for (final (i, c) in _categories.indexed) {
      if (c.name == next.name) _categories[i] = next;
    }
    notifyListeners();
  }

  /// Renames a category and every entry, budget and recurring item that
  /// uses it.
  void renameCategory(String from, String to) {
    if (from == to || to.isEmpty) return;
    for (final (i, c) in _categories.indexed) {
      if (c.name == from) {
        _categories[i] = Category(to, c.icon, c.color, income: c.income);
      }
    }
    for (final (i, e) in _entries.indexed) {
      if (e.category == from) _entries[i] = e.withCategory(to);
    }
    for (final (i, b) in _budgets.indexed) {
      if (b.category == from) _budgets[i] = Budget(to, b.limit);
    }
    for (final (i, r) in _recurring.indexed) {
      if (r.category == from) {
        _recurring[i] = Recurring(
          id: r.id,
          name: r.name,
          amount: r.amount,
          day: r.day,
          account: r.account,
          category: to,
          active: r.active,
        );
      }
    }
    notifyListeners();
  }

  void toggleRecurring(String id) {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index < 0) return;
    _recurring[index] = _recurring[index].toggled();
    notifyListeners();
  }

  /// Books [item] for this month on its day, or today if that is later.
  void confirm(Recurring item) {
    final day = item.day.clamp(1, 28);
    final date = DateTime.utc(today.year, today.month, day);
    add(
      Entry(
        id: newId(),
        date: date.isAfter(today) ? today : date,
        type: EntryType.expense,
        amount: item.amount,
        account: item.account,
        category: item.category,
        note: item.name,
        recurring: item.id,
      ),
    );
  }

  /// Replaces everything with the contents of [fresh], for a demo reset.
  void resetTo(Ledger fresh) {
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
    hidden = false;
    amountsHidden = false;
    _replay();
    notifyListeners();
  }

  void addRecurring(Recurring item) {
    _recurring.add(item);
    notifyListeners();
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

  /// Rebuilds the holdings and their lots from the starting positions and
  /// every investment entry in date order.
  void _replay() {
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
        case EntryType.dividend:
          byCode[code] = held.copyWith(dividends: held.dividends + e.amount);
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
