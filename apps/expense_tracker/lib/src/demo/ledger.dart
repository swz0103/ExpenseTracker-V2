import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

/// What an entry does. Buys, sells and dividends are investment entries.
enum EntryType { expense, income, transfer, buy, sell, dividend }

enum AccountKind { cash, bank, wallet, card }

final class Account {
  const Account(this.id, this.name, this.kind, this.opening);

  final String id;
  final String name;
  final AccountKind kind;

  /// The balance before the first entry; negative for card debt.
  final int opening;
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
    int? cost,
    int? dividends,
    int? realized,
  }) => Holding(
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

  final DateTime today;
  final List<Account> _accounts;
  final List<Category> _categories;
  final List<Entry> _entries;
  final List<Holding> _startHoldings;
  final List<Budget> _budgets;
  final List<Recurring> _recurring;
  var _holdings = <Holding>[];
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
  int income(int year, int month) => _sum(
    entriesIn(year, month).where(
      (e) => e.type == EntryType.income || e.type == EntryType.dividend,
    ),
  );

  int expense(int year, int month, {int? untilDay}) => _sum(
    entriesIn(year, month).where(
      (e) =>
          e.type == EntryType.expense &&
          (untilDay == null || e.date.day <= untilDay),
    ),
  );

  int dividends(int year, int month) => _sum(
    entriesIn(year, month).where((e) => e.type == EntryType.dividend),
  );

  int spentOn(DateTime day) =>
      _sum(entriesOn(day).where((e) => e.type == EntryType.expense));

  /// A month's spending by category, largest first.
  List<(Category, int)> expenseByCategory(
    int year,
    int month, {
    int? untilDay,
  }) {
    final totals = <String, int>{};
    for (final e in entriesIn(year, month)) {
      if (e.type != EntryType.expense) continue;
      if (untilDay != null && e.date.day > untilDay) continue;
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    }
    final rows = [
      for (final MapEntry(:key, :value) in totals.entries)
        (category(key), value),
    ];
    rows.sort((a, b) => b.$2.compareTo(a.$2));
    return rows;
  }

  // Balances.

  int _effect(Entry e, String account) {
    var change = 0;
    if (e.account == account) {
      change += switch (e.type) {
        EntryType.income || EntryType.sell || EntryType.dividend => e.amount,
        _ => -e.amount,
      };
    }
    if (e.type == EntryType.transfer && e.to == account) change += e.amount;
    return change;
  }

  /// The balance of [account] at the end of [until], or of today.
  int balance(String account, {DateTime? until}) {
    final end = until ?? today;
    var total = this.account(account).opening;
    for (final e in _entries) {
      if (!e.date.isAfter(end)) total += _effect(e, account);
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
          change += _effect(e, account);
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
      if (e.category == from) {
        _entries[i] = Entry(
          id: e.id,
          date: e.date,
          type: e.type,
          amount: e.amount,
          account: e.account,
          category: to,
          note: e.note,
          to: e.to,
          holding: e.holding,
          shares: e.shares,
          recurring: e.recurring,
        );
      }
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
    _replay();
    notifyListeners();
  }

  void addRecurring(Recurring item) {
    _recurring.add(item);
    notifyListeners();
  }

  void toggleHidden() {
    hidden = !hidden;
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

  /// Rebuilds the holdings from the starting positions and every
  /// investment entry in date order.
  void _replay() {
    final byCode = {for (final h in _startHoldings) h.code: h};
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
          byCode[code] = held.copyWith(
            shares: held.shares + e.shares,
            cost: held.cost + e.amount,
          );
        case EntryType.sell:
          if (e.shares > held.shares) {
            throw StateError('賣出股數超過持有股數');
          }
          final part = held.shares == 0
              ? 0
              : (held.cost * e.shares / held.shares).round();
          byCode[code] = held.copyWith(
            shares: held.shares - e.shares,
            cost: held.cost - part,
            realized: held.realized + e.amount - part,
          );
        case EntryType.dividend:
          byCode[code] = held.copyWith(dividends: held.dividends + e.amount);
        default:
          break;
      }
    }
    _holdings = [
      for (final h in byCode.values)
        if (h.shares > 0 || h.realized != 0) h,
    ]..sort((a, b) => b.value.compareTo(a.value));
  }
}
