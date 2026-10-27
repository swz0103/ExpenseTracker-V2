import 'dart:collection' show UnmodifiableListView;
import 'dart:convert';
import 'dart:math';

import 'package:core/foundation_values.dart'
    show BusinessDate, Currency, PublicId;
import 'package:domain/credit_cards.dart' show CardScheduleChange;
import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, ValueNotifier;
import 'package:flutter/painting.dart' show Color;

import 'amounts.dart';
import 'card_cycle.dart';
import 'journal.dart';
import 'portfolio.dart';
import 'records.dart';

export 'card_cycle.dart';
export 'records.dart';

part 'ledger_cards.dart';
part 'ledger_planning.dart';
part 'ledger_reports.dart';

/// The screens' book: accounts, categories, entries, holdings, budgets
/// and recurring items, with the sums the screens show. Holdings are
/// replayed from the starting positions and the investment entries, so
/// edits and deletions always recompute them.
final class Ledger extends ChangeNotifier {
  Ledger({
    required DateTime today,
    DateTime Function()? clock,
    required List<Account> accounts,
    required List<Category> categories,
    required List<Entry> entries,
    required List<Holding> holdings,
    required List<Budget> budgets,
    required List<Recurring> recurring,
    this.journal,
    Map<String, double> rates = const {},
    List<Trashed> trash = const [],
    Map<String, double> moves = const {},
    DateTime? quotedOn,
    Map<String, String> receipts = const {},
    Map<String, String> drafts = const {},
  }) : _clock = clock ?? (() => today),
       _drafts = {...drafts},
       _day = today,
       _quotedOn = quotedOn,
       _receipts = {...receipts},
       _rates = {...rates},
       _moves = {...moves},
       _trash = [...trash],
       _accounts = [...accounts],
       _categories = [...categories],
       _entries = [...entries],
       _startHoldings = [...holdings],
       _budgets = [...budgets],
       _recurring = [...recurring] {
    _replay(lenient: true);
  }

  static const allSpending = '全部支出';

  /// Today, as a UTC midnight: from the clock, so a ledger left open
  /// past midnight moves on to the new day.
  DateTime get today => _clock();
  final DateTime Function() _clock;

  /// The day the screens last showed.
  DateTime _day;

  /// Tells the screens when the day has changed since they last looked,
  /// as when the app comes back the next morning.
  void checkDay() {
    final now = today;
    if (now == _day) return;
    _day = now;
    // What was worked out for yesterday, such as the last statement,
    // is worked out again.
    notifyListeners();
  }

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

  /// Entries deleted lately, newest first, until restored.
  final List<Trashed> _trash;

  /// The photo of each entry's receipt, by entry id: a file name the
  /// phone keeps.
  final Map<String, String> _receipts;

  /// The receipt photo of the entry with [id]; null when none.
  String? receiptOf(String id) => _receipts[id];

  /// Every receipt photo an entry keeps, deleted entries' included.
  Set<String> get receiptFiles => {
    ..._receipts.values,
    // A form put aside keeps the photo chosen for it.
    for (final draft in _drafts.values)
      if (_draftReceipt(draft) case final file?) file,
  };

  static String? _draftReceipt(String draft) {
    try {
      return (jsonDecode(draft) as Map<String, Object?>)['receipt'] as String?;
    } on Object {
      return null;
    }
  }

  /// The forms put aside in the composer, as JSON by tab, kept across a
  /// restart of the app.
  final Map<String, String> _drafts;

  String? draft(String tab) => _drafts[tab];

  /// Keeps the form put aside on [tab], or clears it when [json] is null.
  void setDraft(String tab, String? json) {
    if (_drafts[tab] == json) return;
    if (json == null) {
      _drafts.remove(tab);
    } else {
      _drafts[tab] = json;
    }
    _keep(Batch(drafts: {tab: json}));
  }

  /// Gives the entry with [id] the receipt photo [file], or takes its
  /// photo away when null.
  void setReceipt(String id, String? file) {
    if (receiptOf(id) == file) return;
    _receipts.remove(id);
    if (file != null) _receipts[id] = file;
    _signal();
    _keep(Batch(receipts: {id: file}));
  }

  /// The trading day of the newest closing price the holdings are
  /// valued at; null when none was fetched yet.
  DateTime? get quotedOn => _quotedOn;

  /// Whether [code] has a fetched close, rather than the price it was
  /// last bought at standing in for one.
  bool hasQuote(String code) => _startHoldings.any((h) => h.code == code);
  DateTime? _quotedOn;

  /// Each stock's change on its last trading day, per share, by code.
  final Map<String, double> _moves;
  final Map<String, double> _rates;

  /// The holdings replayed from [_startHoldings] and the entries.
  late Portfolio _portfolio;

  /// The holdings replayed, with the day's change where a close gave one.
  List<Holding> get _holdings => _moved ??= [
    for (final h in _portfolio.holdings)
      if (_moves[h.code] case final move?)
        h.withChange((h.shares * move).round())
      else
        h,
  ];
  List<Holding>? _moved;

  /// Amounts are written as dots: the 隱藏金額 switch.
  bool get hidden => _hidden;
  var _hidden = false;

  List<Account> get accounts => List.unmodifiable(_accounts);
  List<Category> get categories => List.unmodifiable(_categories);
  List<Holding> get holdings => UnmodifiableListView(_holdings);
  List<Budget> get budgets => List.unmodifiable(_budgets);
  List<Recurring> get recurring => List.unmodifiable(_recurring);
  List<Trashed> get trash => List.unmodifiable(_trash);

  /// Categories offered for new entries: open ones of the kind.
  List<Category> categoriesFor({required bool income}) => [
    for (final c in _categories)
      if (c.income == income && !c.archived) c,
  ];

  /// Whether [id] is an account of this book, archived ones included.
  bool hasAccount(String id) =>
      (_accountIndex ??= {for (final a in _accounts) a.id: a}).containsKey(id);

  Account account(String id) {
    final accounts = _accountIndex ??= {for (final a in _accounts) a.id: a};
    return accounts[id] ?? Account(id, id, AccountKind.bank, 0);
  }

  Category category(String name) =>
      (_categoryIndex ??= {for (final c in _categories) c.name: c})[name] ??
      Category(name, 'other', const Color(0xFF8C8C80));

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
  Map<String, _Running>? _running;
  final _balances = <(String, DateTime), int>{};
  Map<String, Account>? _accountIndex;
  Map<String, Entry>? _idIndex;
  Map<String, int>? _refundIndex;

  /// Sums worked out since the last change of what they rest on, by what
  /// was asked: such as a card's statement on a given day.
  final _memo = <Object, Object?>{};

  /// What each sum in [_memo] rests on.
  final _memoOn = <Object, Set<Area>>{};

  /// What [make] works out, once per change of the [on] areas for each
  /// [key]. A key should hold every argument the answer depends on, the
  /// day included; [on] is every area it reads.
  T _remember<T>(Object key, T Function() make, {Set<Area> on = Area.all}) {
    if (_memo.containsKey(key)) return _memo[key] as T;
    final made = make();
    _memo[key] = made;
    _memoOn[key] = on;
    return made;
  }

  /// Moves on with every change of what the sums are worked out from, so
  /// a screen that keeps sums of its own knows when to work them out
  /// again; hiding the amounts leaves it.
  int get revision => _revision;
  var _revision = 0;

  /// How many times each area has changed, for a screen that keeps sums
  /// resting on some areas only.
  int revisionOf(Area area) => _areaRevisions[area.index];
  final _areaRevisions = List.filled(Area.values.length, 0);

  Map<String, Category>? _categoryIndex;

  /// Throws away what rests on [areas], and only that: a budget changed
  /// leaves every statement and balance worked out.
  void _forget(Set<Area> areas) {
    _revision++;
    for (final area in areas) {
      _areaRevisions[area.index]++;
    }
    if (areas.contains(Area.categories)) _categoryIndex = null;
    if (areas.contains(Area.entries)) {
      _idIndex = null;
      _refundIndex = null;
      _months = null;
      _days = null;
      _first = null;
    }
    if (areas.contains(Area.entries) || areas.contains(Area.accounts)) {
      _running = null;
      _balances.clear();
    }
    if (areas.contains(Area.accounts)) _accountIndex = null;
    if (areas.contains(Area.entries) || areas.contains(Area.market)) {
      _moved = null;
    }
    final stale = [
      for (final MapEntry(:key, value: on) in _memoOn.entries)
        if (on.any(areas.contains)) key,
    ];
    for (final key in stale) {
      _memo.remove(key);
      _memoOn.remove(key);
    }
  }

  /// Tells the screens of a change of every area.
  @override
  void notifyListeners() => _changed(Area.all);

  /// Tells the screens [areas] changed, after throwing away what rests on
  /// them; those listening to [watch] hear only of the areas they asked
  /// for.
  void _changed(Set<Area> areas) {
    _forget(areas);
    super.notifyListeners();
    for (final area in areas) {
      _watchers[area]?.notify();
    }
  }

  /// Tells the screens of a change that leaves every sum as it was, such
  /// as hiding the amounts: nothing worked out is thrown away.
  void _signal() {
    super.notifyListeners();
    _watchers[Area.display]?.notify();
  }

  final _watchers = <Area, _Watcher>{};

  /// Changes of [areas] only, and of how amounts are shown: for a screen
  /// that need not be built again when, say, a budget changes.
  Listenable watch(Set<Area> areas) => Listenable.merge([
    for (final area in {...areas, Area.display})
      _watchers[area] ??= _Watcher(),
  ]);

  /// Every entry, in the order written; the list cannot be changed.
  List<Entry> get entries => UnmodifiableListView(_entries);

  /// Entries of any month whose note, merchant, category or tags hold
  /// [words], or whose amount is [words]; newest first.
  List<Entry> search(String words) =>
      _remember(
        ('search', words),
        () => _search(words),
        on: const {Area.entries, Area.accounts, Area.categories},
      );

  List<Entry> _search(String words) {
    final lower = words.toLowerCase();
    // Each entry's words, lower-cased once per change.
    final texts = _remember(
      'searchText',
      () => [
        for (final e in _entries)
          [e.note, e.merchant, e.category, ...e.tags].join('\n').toLowerCase(),
      ],
      on: const {Area.entries},
    );
    final found = [
      for (final (i, e) in _entries.indexed)
        if (texts[i].contains(lower) ||
            '${e.amount}' == words ||
            plainIn(e.amount, account(e.account).currency) == words)
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

  // Changes.

  String newId() => PublicId.generate().value;

  var _queue = Future<void>.value();
  var _waiting = 0;

  /// Done once every change so far has reached the [journal].
  Future<void> get settled => _queue;

  /// Whether a refused change left the screens ahead of the [journal].
  var _stale = false;

  /// Hands [batch] to the [journal], in turn with every change before it.
  /// A batch it refuses is reported through [problem], and once nothing
  /// else waits the book is read back, so the screens show what was kept.
  void _keep(Batch batch) {
    final journal = this.journal;
    if (journal == null || batch.isEmpty) return;
    _waiting++;
    _queue = _queue.then((_) async {
      try {
        await journal.keep(batch);
      } on Object catch (error) {
        problem.value = error;
        _stale = true;
      }
      if (--_waiting > 0 || !_stale) return;
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

  /// Takes new closing prices and rates: the stocks' reference prices and
  /// names in [holdings], each day's change in [moves].
  void setMarket({
    required List<Holding> holdings,
    required Map<String, double> moves,
    required Map<String, double> rates,
    DateTime? quotedOn,
  }) {
    _startHoldings
      ..clear()
      ..addAll(holdings);
    _moves
      ..clear()
      ..addAll(moves);
    _rates
      ..clear()
      ..addAll(rates);
    _quotedOn = quotedOn;
    _replay(lenient: true);
    _changed(const {Area.market});
  }

  /// What a change of several records left different: every record not
  /// the very one it was before is kept, and those gone are dropped.
  Batch _since(_Before before) {
    List<T> changed<T>(List<T> was, List<T> now, String Function(T) key) {
      final old = {for (final item in was) key(item): item};
      return [
        for (final item in now)
          if (!identical(old[key(item)], item)) item,
      ];
    }

    List<(Shelf, String)> gone<T>(
      Shelf shelf,
      List<T> was,
      List<T> now,
      String Function(T) key,
    ) {
      final kept = {for (final item in now) key(item)};
      return [
        for (final item in was)
          if (!kept.contains(key(item))) (shelf, key(item)),
      ];
    }

    String entryKey(Entry e) => e.id;
    String categoryKey(Category c) => c.name;
    String budgetKey(Budget b) => b.category;
    String recurringKey(Recurring r) => r.id;
    return Batch(
      entries: changed(before.entries, _entries, entryKey),
      categories: changed(before.categories, _categories, categoryKey),
      budgets: changed(before.budgets, _budgets, budgetKey),
      recurring: changed(before.recurring, _recurring, recurringKey),
      dropped: [
        ...gone(Shelf.entry, before.entries, _entries, entryKey),
        ...gone(Shelf.category, before.categories, _categories, categoryKey),
        ...gone(Shelf.budget, before.budgets, _budgets, budgetKey),
        ...gone(Shelf.recurring, before.recurring, _recurring, recurringKey),
      ],
    );
  }

  _Before get _before => (
    entries: List.of(_entries),
    categories: List.of(_categories),
    budgets: List.of(_budgets),
    recurring: List.of(_recurring),
  );

  /// Adds [entry], with its receipt photo [receipt] when one is given; a
  /// sale of more shares than are held is refused with a [StateError].
  void add(Entry entry, {String? receipt}) {
    _entries.add(entry);
    _replayOrUndo(() => _entries.removeLast(), trades: entry.isInvestment);
    if (receipt != null) _receipts[entry.id] = receipt;
    _keep(
      Batch(
        entries: [entry],
        receipts: {if (receipt != null) entry.id: receipt},
      ),
    );
  }

  /// Adds every one of [entries] at once, with the [accounts] and
  /// [categories] they bring, as an import does: all of it is kept
  /// together, or none.
  void addAll(
    List<Entry> entries, {
    List<Account> accounts = const [],
    List<Category> categories = const [],
  }) {
    if (entries.isEmpty && accounts.isEmpty && categories.isEmpty) return;
    final count = _entries.length;
    _entries.addAll(entries);
    _replayOrUndo(
      () => _entries.removeRange(count, _entries.length),
      trades: entries.any((e) => e.isInvestment),
    );
    final seen = <String>{};
    final named = [
      for (final c in categories)
        if (categoryNameFree(c.name) && seen.add(c.name.trim())) c,
    ];
    final ids = {for (final a in _accounts) a.id};
    final opened = [
      for (final a in accounts)
        if (ids.add(a.id)) a,
    ];
    _accounts.addAll(opened);
    _categories.addAll(named);
    notifyListeners();
    _keep(Batch(accounts: opened, categories: named, entries: entries));
  }

  /// Puts [entry] in place of the entry with the same id, with the receipt
  /// photo [receipt] (null takes it away).
  void replace(Entry entry, {String? receipt}) {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index < 0) return add(entry, receipt: receipt);
    final before = _entries[index];
    _entries[index] = entry;
    _replayOrUndo(
      () => _entries[index] = before,
      trades: entry.isInvestment || before.isInvestment,
    );
    final photo = _receipts[entry.id] != receipt;
    if (receipt == null) {
      _receipts.remove(entry.id);
    } else {
      _receipts[entry.id] = receipt;
    }
    _keep(Batch(entries: [entry], receipts: {if (photo) entry.id: receipt}));
  }

  /// Puts each of [entries] in place of the one with the same id, as one
  /// change; those the ledger does not hold are left out.
  void replaceAll(List<Entry> entries) {
    final before = <int, Entry>{};
    for (final e in entries) {
      final index = _entries.indexWhere((x) => x.id == e.id);
      if (index < 0) continue;
      before.putIfAbsent(index, () => _entries[index]);
      _entries[index] = e;
    }
    if (before.isEmpty) return;
    _replayOrUndo(() {
      for (final MapEntry(key: index, value: e) in before.entries) {
        _entries[index] = e;
      }
    }, trades: [...before.values, ...entries].any((e) => e.isInvestment));
    _keep(Batch(entries: [for (final i in before.keys) _entries[i]]));
  }

  /// Removes the entry with [id] and returns it with its place, for undo.
  /// Null when there is none, or when taking it away would leave a later
  /// sale short of shares: that is told through [problem].
  (int, Entry)? remove(String id) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return null;
    final removed = _entries.removeAt(index);
    if (!_tryReplay(
      () => _entries.insert(index, removed),
      trades: removed.isInvestment,
    )) {
      return null;
    }
    final trashed = Trashed(removed, today);
    _trash.insert(0, trashed);
    _keep(Batch(trash: [trashed], dropped: [(Shelf.entry, removed.id)]));
    return (index, removed);
  }

  /// Removes every entry of [ids] as one change, and returns each with its
  /// place, for undo; none when taking them away would leave a later sale
  /// short of shares, which is told through [problem].
  List<(int, Entry)> removeAll(Iterable<String> ids) {
    final wanted = {...ids};
    final removed = <(int, Entry)>[
      for (final (i, e) in _entries.indexed)
        if (wanted.contains(e.id)) (i, e),
    ];
    if (removed.isEmpty) return const [];
    _entries.removeWhere((e) => wanted.contains(e.id));
    if (!_tryReplay(() {
      for (final (i, e) in removed) {
        _entries.insert(i, e);
      }
    }, trades: removed.any((r) => r.$2.isInvestment))) {
      return const [];
    }
    final trashed = [for (final (_, e) in removed) Trashed(e, today)];
    _trash.insertAll(0, trashed.reversed);
    _keep(
      Batch(
        trash: trashed,
        dropped: [for (final (_, e) in removed) (Shelf.entry, e.id)],
      ),
    );
    return removed;
  }

  /// Puts back what [removeAll] took away, as one change.
  bool restoreAll(List<(int, Entry)> removed) {
    if (removed.isEmpty) return true;
    final ids = {for (final (_, e) in removed) e.id};
    if (_entries.any((e) => ids.contains(e.id))) return false;
    for (final (i, e) in removed) {
      _entries.insert(i.clamp(0, _entries.length), e);
    }
    if (!_tryReplay(
      () => _entries.removeWhere((e) => ids.contains(e.id)),
      trades: removed.any((r) => r.$2.isInvestment),
    )) {
      return false;
    }
    _trash.removeWhere((t) => ids.contains(t.entry.id));
    _keep(
      Batch(
        entries: [for (final (_, e) in removed) e],
        dropped: [for (final id in ids) (Shelf.trash, id)],
      ),
    );
    return true;
  }

  /// Puts back an entry [remove] took away. False, told through
  /// [problem], when it no longer fits the trades kept since.
  bool restore((int, Entry) removed) {
    final (index, entry) = removed;
    if (byId(entry.id) != null) return false;
    _entries.insert(index.clamp(0, _entries.length), entry);
    if (!_tryReplay(() => _entries.remove(entry), trades: entry.isInvestment)) {
      return false;
    }
    _trash.removeWhere((t) => t.entry.id == entry.id);
    _keep(Batch(entries: [entry], dropped: [(Shelf.trash, entry.id)]));
    return true;
  }

  /// Puts [trashed] back in the book. False, told through [problem], when
  /// it no longer fits the trades kept since.
  bool restoreTrashed(Trashed trashed) {
    final entry = trashed.entry;
    if (byId(entry.id) != null) {
      // Already back in the book, as by an undo: only the trash keeps it.
      _trash.removeWhere((t) => t.entry.id == entry.id);
      _signal();
      _keep(Batch(dropped: [(Shelf.trash, entry.id)]));
      return true;
    }
    final at = _trash.indexOf(trashed);
    _trash.remove(trashed);
    _entries.add(entry);
    if (!_tryReplay(() {
      _entries.removeLast();
      _trash.insert(at < 0 ? 0 : at, trashed);
    }, trades: entry.isInvestment)) {
      return false;
    }
    _keep(Batch(entries: [entry], dropped: [(Shelf.trash, entry.id)]));
    return true;
  }

  void setBudget(String category, int limit, {int? warning, bool? carry}) {
    final old = budgetFor(category);
    _budgets.removeWhere((b) => b.category == category);
    final budget = Budget(
      category,
      limit,
      warning: warning ?? old.warning,
      carry: carry ?? old.carry,
      since: old.since ?? DateTime.utc(today.year, today.month),
    );
    _budgets.add(budget);
    _changed(const {Area.budgets});
    _keep(Batch(budgets: [budget]));
  }

  void removeBudget(String category) {
    _budgets.removeWhere((b) => b.category == category);
    _changed(const {Area.budgets});
    _keep(Batch(dropped: [(Shelf.budget, category)]));
  }

  void addAccount(Account account) {
    _accounts.add(account);
    _changed(const {Area.accounts});
    _keep(Batch(accounts: [account]));
  }

  /// Puts [account] in place of the one with the same id.
  void updateAccount(Account account) {
    final index = _accounts.indexWhere((a) => a.id == account.id);
    if (index < 0) return addAccount(account);
    final before = _accounts[index];
    // A form that does not show a card's moved closes and earlier billing
    // days keeps them.
    account = account.copyWith(
      closes: account.closes.isEmpty ? before.closes : null,
      history: account.history.isEmpty ? before.history : null,
    );
    account = _rescheduled(before, account);
    _accounts[index] = account;
    _changed(const {Area.accounts});
    _keep(Batch(accounts: [account]));
  }

  /// [after] keeping [before]'s billing days for the statements closing
  /// before the next close on the new day, as the ledger keeps them.
  Account _rescheduled(Account before, Account after) {
    final closing = before.closingDay;
    final due = before.dueDay;
    if (after.kind != AccountKind.card ||
        closing == null ||
        due == null ||
        ((after.closingDay ?? closing) == closing &&
            (after.dueDay ?? due) == due)) {
      return after;
    }
    final day = after.closingDay ?? closing;
    var from = DateTime.utc(today.year, today.month + 1, 0);
    for (final month in [today.month, today.month + 1]) {
      final last = DateTime.utc(today.year, month + 1, 0);
      final close = DateTime.utc(last.year, last.month, min(day, last.day));
      if (close.isAfter(today)) {
        from = close;
        break;
      }
    }
    final until = BusinessDate(from.year, from.month, from.day);
    final kept = before.history;
    // Days changed again before the last change took effect: the days
    // before that one still hold until the first close on the newest.
    final pending =
        kept.isNotEmpty &&
        kept.last.until.compareTo(
              BusinessDate(today.year, today.month, today.day),
            ) >
            0;
    return after.copyWith(
      history: [
        ...(pending ? kept.sublist(0, kept.length - 1) : kept),
        CardScheduleChange(
          until: until,
          closingDay: pending ? kept.last.closingDay : closing,
          dueDay: pending ? kept.last.dueDay : due,
        ),
      ],
    );
  }

  /// Corrects [id]'s balance today to [target] by moving its opening
  /// balance, so its history keeps its shape.
  void setBalance(String id, int target) {
    final index = _accounts.indexWhere((a) => a.id == id);
    if (index < 0) return;
    final a = _accounts[index];
    final moved = a.copyWith(opening: a.opening + target - balance(id));
    _accounts[index] = moved;
    _changed(const {Area.accounts});
    _keep(Batch(accounts: [moved]));
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
    _keep(Batch(accounts: [moved]));
  }

  /// Whether [id] has any entries; an account without can be removed.
  bool isUsed(String id) => _entries.any((e) => e.account == id || e.to == id);

  void removeAccount(String id) {
    if (isUsed(id)) return;
    final index = _accounts.indexWhere((a) => a.id == id);
    if (index < 0) return;
    final removed = _accounts.removeAt(index);
    notifyListeners();
    _keep(Batch(dropped: [(Shelf.account, removed.id)]));
  }

  /// Whether [name] can be a new category's: not empty, not one the
  /// ledger keeps for itself (all spending, transfers, a `#` tag budget)
  /// and not taken, unless by [except].
  bool categoryNameFree(String name, {String? except}) {
    final trimmed = name.trim();
    // A category keeps its own name, even one from before these rules.
    if (except != null && trimmed == except) return true;
    if (trimmed.isEmpty ||
        trimmed == allSpending ||
        trimmed == transferCategory ||
        trimmed.startsWith('#')) {
      return false;
    }
    return !_categories.any((c) => c.name == trimmed);
  }

  void addCategory(Category category) {
    if (!categoryNameFree(category.name)) {
      problem.value = const NameTaken();
      return;
    }
    _categories.add(category);
    _changed(const {Area.categories});
    _keep(Batch(categories: [category]));
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
        _budgets[i] = b.renamed(to);
      }
    }
    _oneBudgetEach();
    notifyListeners();
  }

  /// Keeps the first budget of each name, as a rename onto a name that
  /// had one leaves two.
  void _oneBudgetEach() {
    final seen = <String>{};
    _budgets.retainWhere((b) => seen.add(b.category));
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
      home: currency == homeCode ? null : toHome(item.amount, currency),
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
    _changed(const {Area.recurring});
    _keep(Batch(recurring: [item]));
  }

  void removeRecurring(String id) {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index < 0) return;
    final removed = _recurring.removeAt(index);
    _changed(const {Area.recurring});
    _keep(Batch(dropped: [(Shelf.recurring, removed.id)]));
  }

  /// Changes a category's place, name, mark, colour or archive state; a
  /// new name reaches every entry, budget and recurring item that uses it.
  void updateCategory(String name, Category next) {
    final index = _categories.indexWhere((c) => c.name == name);
    if (index < 0) return;
    if (!categoryNameFree(next.name, except: name)) {
      problem.value = const NameTaken();
      return;
    }
    final before = _before;
    if (next.name != name) _renameCategory(name, next.name);
    _categories[index] = next;
    notifyListeners();
    _keep(_since(before));
  }

  /// Moves everything in [from] to [into] and removes [from].
  void mergeCategory(String from, String into) {
    if (from == into) return;
    final before = _before;
    _moveUses(from, into);
    _budgets.removeWhere((b) => b.category == from);
    _categories.removeWhere((c) => c.name == from);
    for (final (i, c) in _categories.indexed) {
      if (c.parent == from) _categories[i] = c.copyWith(clearParent: true);
    }
    notifyListeners();
    _keep(_since(before));
  }

  /// Renames or merges a tag across every entry; an empty [to] removes it.
  void renameTag(String from, String to) {
    final before = _before;
    for (final (i, b) in _budgets.indexed) {
      if (b.tag == from && to.isNotEmpty) {
        _budgets[i] = b.renamed('#$to');
      }
    }
    if (to.isEmpty) _budgets.removeWhere((b) => b.tag == from);
    _oneBudgetEach();
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
    _keep(_since(before));
  }

  /// Renames or merges a merchant across every entry; an empty [to]
  /// clears it.
  void renameMerchant(String from, String to) {
    final before = _before;
    for (final (i, e) in _entries.indexed) {
      if (e.merchant == from) _entries[i] = e.withLabels(merchant: to);
    }
    notifyListeners();
    _keep(_since(before));
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
    _trash
      ..clear()
      ..addAll(fresh._trash);
    _moves
      ..clear()
      ..addAll(fresh._moves);
    _receipts
      ..clear()
      ..addAll(fresh._receipts);
    _drafts
      ..clear()
      ..addAll(fresh._drafts);
    _quotedOn = fresh._quotedOn;
    _day = fresh.today;
    _replay(lenient: true);
    notifyListeners();
  }

  void toggleHidden() {
    _hidden = !_hidden;
    _signal();
  }

  /// Works the holdings out again when [trades] were touched, then tells
  /// the screens; an oversold trade is undone and rethrown.
  void _replayOrUndo(void Function() undo, {bool trades = true}) {
    if (trades) {
      try {
        _replay();
      } on StateError {
        undo();
        _replay();
        rethrow;
      }
    }
    notifyListeners();
  }

  /// [_replayOrUndo], telling a refusal through [problem] rather than
  /// throwing; false when refused.
  bool _tryReplay(void Function() undo, {required bool trades}) {
    try {
      _replayOrUndo(undo, trades: trades);
      return true;
    } on StateError {
      problem.value = const SharesShort();
      notifyListeners();
      return false;
    }
  }

  /// Whether [extra] can join the entries, in place of [replacing]: none
  /// of their trades sells more shares than are held by then.
  bool holdsWith(List<Entry> extra, {Entry? replacing}) {
    try {
      Portfolio.replay(_startHoldings, [
        for (final e in _entries)
          if (replacing == null || e.id != replacing.id) e,
        ...extra,
      ]);
      return true;
    } on StateError {
      return false;
    }
  }

  /// Rebuilds the holdings from the starting positions and every
  /// investment entry; an oversold trade throws a [StateError], or, when
  /// [lenient], as for a book just loaded, is left out of the holdings.
  void _replay({bool lenient = false}) {
    // The caller says what changed (_changed); the day's moves rest on
    // the holdings, so they go now.
    _moved = null;
    _portfolio = Portfolio.replay(_startHoldings, _entries, lenient: lenient);
  }
}

/// One account's entries in date order with the balance change up to each
/// of them, so a balance on any day is one search. Instalment purchases
/// are kept apart: what they have billed depends on the day asked about.
/// The parts of the book a change can touch, so what rests on the others
/// is kept.
enum Area {
  entries,
  accounts,
  categories,
  budgets,
  recurring,
  market,

  /// How amounts are shown (隱藏金額); nothing worked out rests on it.
  display;

  /// Every part of the book.
  static const all = {
    entries,
    accounts,
    categories,
    budgets,
    recurring,
    market,
  };
}

/// One area's listeners.
final class _Watcher extends ChangeNotifier {
  void notify() => notifyListeners();
}

final class _Running {
  final days = <DateTime>[];
  final totals = <int>[];
  final plans = <Entry>[];

  /// The change of the entries on or before [day].
  int until(DateTime day) {
    var low = 0;
    var high = days.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (days[middle].isAfter(day)) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low == 0 ? 0 : totals[low - 1];
  }
}

/// The records a change of several may touch, as they were before it.
typedef _Before = ({
  List<Entry> entries,
  List<Category> categories,
  List<Budget> budgets,
  List<Recurring> recurring,
});

/// A change was refused because it would leave a later sale or reduction
/// of a stock short of shares.
final class SharesShort implements Exception {
  const SharesShort();

  @override
  String toString() => 'SharesShort';
}

/// A category was not added or renamed: its name is empty, taken, or one
/// the ledger keeps for itself.
final class NameTaken implements Exception {
  const NameTaken();

  @override
  String toString() => 'NameTaken';
}
