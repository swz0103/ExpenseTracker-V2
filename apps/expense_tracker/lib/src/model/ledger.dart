import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:foundation_values/foundation_values.dart'
    show Currency, PublicId;

import '../book/journal.dart';
import 'amounts.dart';
import 'card_cycle.dart';
import 'portfolio.dart';
import 'records.dart';

export 'card_cycle.dart';
export 'records.dart';

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
    Map<String, int> cardDues = const {},
  }) : _rates = {...rates},
       _dues = {...cardDues},
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

  /// Each card's [statementDue] as the journal's billing has it, by id.
  final Map<String, int> _dues;

  /// The holdings replayed from [_startHoldings] and the entries.
  late Portfolio _portfolio;

  List<Holding> get _holdings => _portfolio.holdings;

  /// Amounts are written as dots: the 隱藏金額 switch.
  bool get hidden => _hidden;
  var _hidden = false;

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
  List<Lot> lotsOf(String code) => _portfolio.lotsOf(code);

  /// What selling [shares] of [code] now would cost: the oldest lots
  /// first, or the average price.
  int saleCost(String code, int shares, {bool average = false}) =>
      _portfolio.saleCost(code, shares, average: average);

  Holding? holding(String code) {
    for (final h in _holdings) {
      if (h.code == code) return h;
    }
    return null;
  }

  // Entries.

  /// Entries in [year]/[month], newest day first; within a day the most
  /// recently recorded first. The list cannot be changed.
  List<Entry> entriesIn(int year, int month) {
    final months = _months ??= _indexMonths();
    return months[year * 12 + month] ?? const <Entry>[];
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
      months[month] = List.unmodifiable([for (final (_, e) in found) e]);
    }
    return months;
  }

  /// What the screens ask for again and again, worked out once per change:
  /// entries by month, balances by account and day, accounts by id.
  Map<int, List<Entry>>? _months;
  Map<DateTime, List<Entry>>? _days;
  DateTime? _first;
  final _balances = <(String, DateTime), int>{};
  Map<String, Account>? _accountIndex;

  void _touch() {
    _months = null;
    _days = null;
    _first = null;
    _balances.clear();
    _accountIndex = null;
  }

  @override
  void notifyListeners() {
    _touch();
    super.notifyListeners();
  }

  /// Entries of any month whose note, merchant, category or tags hold
  /// [words], or whose amount is [words]; newest first.
  List<Entry> search(String words) {
    final found = [
      for (final (i, e) in _entries.indexed)
        if (e.note.contains(words) ||
            e.merchant.contains(words) ||
            e.category.contains(words) ||
            e.tags.any((t) => t.contains(words)) ||
            plainIn(e.amount, account(e.account).currency) == words ||
            '${e.amount}' == words)
          (i, e),
    ];
    found.sort((a, b) {
      final byDate = b.$2.date.compareTo(a.$2.date);
      return byDate != 0 ? byDate : b.$1.compareTo(a.$1);
    });
    return [for (final (_, e) in found) e];
  }

  List<Entry> entriesOn(DateTime day) =>
      (_days ??= _indexDays())[day] ?? const [];

  /// Every day's entries in [entriesIn] order, built once per change.
  Map<DateTime, List<Entry>> _indexDays() {
    final days = <DateTime, List<Entry>>{};
    for (final month in (_months ??= _indexMonths()).values) {
      for (final e in month) {
        (days[e.date] ??= []).add(e);
      }
    }
    return days;
  }

  /// Income of a month, dividends included.
  int income(int year, int month) =>
      entriesIn(year, month).fold(0, (total, e) => total + e.earning);

  /// Spending of a month, less refunds, with transfer fees.
  int expense(int year, int month, {int? untilDay}) => entriesIn(year, month)
      .where((e) => untilDay == null || e.date.day <= untilDay)
      .fold(0, (total, e) => total + e.spending);

  int dividends(int year, int month) =>
      entriesIn(year, month).fold(0, (sum, e) => sum + e.dividendNet);

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

  // Balances.

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

  // Cards.

  /// How much of [e] has reached its card's statements by [at]: all of
  /// it, or the instalments billed so far.
  int billed(Entry e, DateTime at) => account(e.account).billed(e, at);

  /// How many instalments of [e] have been billed by [at].
  int billedPeriods(Entry e, DateTime at) =>
      account(e.account).billedPeriods(e, at);

  /// The last day whose statement closes are behind: a statement closes
  /// at the end of its day, so one closing today is still open.
  DateTime get closedBy => today.subtract(const Duration(days: 1));

  /// The last closed statement of [card]: its first and last day and when
  /// it must be paid.
  (DateTime, DateTime, DateTime) statement(Account card) {
    final end = card.closingOn(closedBy);
    final before = card.closingOn(end.subtract(const Duration(days: 1)));
    final start = before.add(const Duration(days: 1));
    // The due day in the close's month, or the next, kept within it.
    DateTime dueIn(int month) {
      final last = DateTime.utc(end.year, month + 1, 0);
      final day = min(card.dueDay ?? 15, last.day);
      return DateTime.utc(last.year, last.month, day);
    }

    final here = dueIn(end.month);
    return (start, end, here.isAfter(end) ? here : dueIn(end.month + 1));
  }

  /// What is still to pay on the last statement of [card]: the journal's
  /// figure once every change has reached it, else [dueFromEntries].
  int statementDue(Account card) {
    final kept = _dues[card.id];
    return kept != null && _waiting == 0 ? kept : dueFromEntries(card);
  }

  /// [statementDue] worked out from the entries, as the screens show it
  /// before a change has been kept.
  int dueFromEntries(Account card) {
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

  /// Purchases on [card] since its last statement closed, and the
  /// refunds and rewards credited against them.
  List<Entry> unbilled(Account card) {
    final (_, end, _) = statement(card);
    bool posted(Entry e) => switch (e.type) {
      EntryType.income => true,
      EntryType.expense => e.installments < 2,
      _ => false,
    };
    return [
      for (final e in _entries)
        if (e.account == card.id && posted(e) && e.date.isAfter(end)) e,
    ]..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Purchases on [card] still being paid in instalments.
  List<Entry> instalmentsOn(Account card) => [
    for (final e in _entries)
      if (e.account == card.id &&
          e.installments > 1 &&
          billedPeriods(e, closedBy) < e.installments)
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
  List<String> get tags => [for (final (tag, _, _) in tagStats) tag];

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

  /// What spending carrying [tag] came to in [year]/[month].
  int spentOnTag(String tag, int year, int month) {
    var total = 0;
    for (final e in entriesIn(year, month)) {
      if (e.tags.contains(tag)) total += e.spending;
    }
    return total;
  }

  Budget budgetFor(String category) => _budgets.firstWhere(
    (b) => b.category == category,
    orElse: () => Budget(category, 0),
  );

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

  /// Whether a change since the last load needs the book read back.
  var _stale = false;

  /// Passes a change to the [journal]. Once nothing else waits, reloads
  /// what was kept, so ids and figures match the store; a refused change
  /// is undone that way and reported through [problem]. A change kept
  /// exactly as the screens already show it skips the reload unless
  /// refused ([reload] false): reading back a large book takes a moment.
  void _keep(
    Future<void> Function(Journal journal) change, {
    bool reload = true,
  }) {
    final journal = this.journal;
    if (journal == null) return;
    _waiting++;
    if (reload) _stale = true;
    _queue = _queue.then((_) async {
      try {
        await change(journal);
      } on Object catch (error) {
        problem.value = error;
        _stale = true;
      }
      if (--_waiting > 0) return;
      if (!_stale) {
        // The journal's card dues may have moved; work them out from the
        // entries until the next load.
        _dues.clear();
        return;
      }
      _stale = false;
      try {
        final fresh = await journal.load();
        // A change made while loading is newer than what was loaded; the
        // load after it brings both.
        if (_waiting == 0) _adopt(fresh);
      } on Object catch (error) {
        problem.value = error;
        _stale = true;
      }
    });
  }

  /// Reloads what the [journal] keeps, such as new closing prices.
  void refresh() => _keep((_) async {});

  /// Adds [entry]; a sale of more shares than are held is refused.
  void add(Entry entry) {
    _entries.add(entry);
    _replayOrUndo(() => _entries.removeLast());
    // An entry with an id of its own is kept under it; any other gets one
    // from the journal, which a reload brings.
    _keep((j) => j.addEntries([entry]), reload: !_isId(entry.id));
  }

  static bool _isId(String id) {
    try {
      PublicId.parse(id);
      return true;
    } on Object {
      return false;
    }
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
    Future<void> change(Journal j) async {
      final stored = _current(before.id);
      final next = await j.replaceEntry(before.withId(stored), entry);
      if (next != stored) _renamed[stored] = next;
    }

    _keep(change, reload: false);
  }

  /// Removes the entry with [id] and returns it with its place, for undo.
  (int, Entry)? remove(String id) {
    final current = _current(id);
    final index = _entries.indexWhere((e) => e.id == current);
    if (index < 0) return null;
    final removed = _entries.removeAt(index);
    _replayOrUndo(() => _entries.insert(index, removed));
    _keep(
      (j) => j.removeEntry(removed.withId(_current(removed.id))),
      reload: false,
    );
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

  /// Moves the close of [cardId]'s statement scheduled on [scheduled] to
  /// [closesOn], up to a week either way, as a bank does around a holiday.
  void moveClose(String cardId, DateTime scheduled, DateTime closesOn) {
    final index = _accounts.indexWhere((a) => a.id == cardId);
    if (index < 0) return;
    final card = _accounts[index];
    final moved = card.copyWith(closes: {...card.closes, scheduled: closesOn});
    _accounts[index] = moved;
    notifyListeners();
    _keep((j) => j.moveClose(moved, scheduled, closesOn));
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

  void _renameCategory(String from, String to) {
    if (from == to || to.isEmpty) return;
    for (final (i, c) in _categories.indexed) {
      if (c.name == from) _categories[i] = c.copyWith(name: to);
      if (c.parent == from) _categories[i] = c.copyWith(parent: to);
    }
    _moveUses(from, to);
    for (final (i, b) in _budgets.indexed) {
      if (b.category == from) {
        _budgets[i] = Budget(to, b.limit, warning: b.warning);
      }
    }
    notifyListeners();
  }

  /// Puts the entries and recurring items of category [from] in [to].
  void _moveUses(String from, String to) {
    for (final (i, e) in _entries.indexed) {
      if (e.category == from || e.parts.any((p) => p.$1 == from)) {
        _entries[i] = e.withCategory(to, from: from);
      }
    }
    for (final (i, r) in _recurring.indexed) {
      if (r.category == from) _recurring[i] = r.copyWith(category: to);
    }
  }

  /// [item]'s amount in whole NT$ at today's rate; 0 without one.
  int recurringWorth(Recurring item) =>
      toHome(item.amount, account(item.account).currency) ?? 0;

  /// The entry that books [item] on its pending day, or today if that is
  /// later, for the composer to show before it is saved. A foreign one
  /// takes its worth at today's rate.
  Entry booking(Recurring item) {
    final date = pendingDate(item) ?? today;
    final currency = account(item.account).currency;
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
      home: currency == 'TWD' ? null : toHome(item.amount, currency),
    );
  }

  /// Books [item] as it stands.
  void confirm(Recurring item) {
    add(booking(item).withId(newId()));
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
    _moveUses(from, into);
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
    for (final (i, b) in _budgets.indexed) {
      if (b.tag == from && to.isNotEmpty) {
        _budgets[i] = Budget('#$to', b.limit, warning: b.warning);
      }
    }
    if (to.isEmpty) _budgets.removeWhere((b) => b.tag == from);
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
    _hidden = false;
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
    _dues
      ..clear()
      ..addAll(fresh._dues);
    _replay();
    notifyListeners();
  }

  void toggleHidden() {
    _hidden = !_hidden;
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
  /// investment entry; an oversold trade throws a [StateError].
  void _replay() {
    _touch();
    _portfolio = Portfolio.replay(_startHoldings, _entries);
  }
}
