import 'dart:collection' show UnmodifiableListView;
import 'dart:convert';
import 'dart:math';

import 'package:core/foundation_values.dart'
    show BusinessDate, Currency, PublicId;
import 'package:domain/credit_cards.dart' show CardScheduleChange;
import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, ValueNotifier;

import '../text/amounts.dart';
import 'card_cycle.dart';
import 'journal.dart';
import 'portfolio.dart';
import 'records.dart';

export 'card_cycle.dart';
export 'records.dart';

part 'ledger_cards.dart';
part 'ledger_planning.dart';
part 'ledger_reports.dart';
part 'ledger_entries.dart';
part 'ledger_queries.dart';
part 'ledger_holdings.dart';
part 'ledger_recurring.dart';
part 'ledger_setup.dart';

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
    this._quotedOn,
    Map<String, DateTime> quoteDays = const {},
    Map<String, String> receipts = const {},
    Map<String, String> drafts = const {},
  }) : _clock = clock ?? (() => today),
       _drafts = {...drafts},
       _day = today,
       _quoteDays = {...quoteDays},
       _receipts = {...receipts},
       _rates = {...rates},
       _moves = {...moves},
       _trash = [...trash],
       _accounts = [...accounts],
       _categories = _placed(categories),
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
    for (final draft in _drafts.values) ?_draftReceipt(draft),
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

  /// The day of [code]'s kept close, when it is older than [quotedOn]:
  /// the last trading day of a stock not traded since, or a close kept
  /// from before when the latest could not be fetched. Null when it is
  /// the latest, or not known.
  DateTime? olderQuote(String code) {
    final day = _quoteDays[code];
    final latest = _quotedOn;
    if (day == null || latest == null || !day.isBefore(latest)) return null;
    return day;
  }

  final Map<String, DateTime> _quoteDays;

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
      Category.unknown(name);

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
    for (final area in {...areas, Area.display}) _watchers[area] ??= _Watcher(),
  ]);

  /// Every entry, in the order written; the list cannot be changed.
  List<Entry> get entries => UnmodifiableListView(_entries);

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
    Map<String, DateTime> quoteDays = const {},
  }) {
    _startHoldings
      ..clear()
      ..addAll(holdings);
    _quoteDays
      ..clear()
      ..addAll(quoteDays);
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
      // Entries in the trash follow a rename or a merge too.
      trash: changed(before.trash, _trash, (t) => t.entry.id),
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
    trash: List.of(_trash),
  );

  /// [categories] with the placed ones first, by place, then the others
  /// in the order they came.
  static List<Category> _placed(List<Category> categories) {
    final indexed = [...categories.indexed];
    indexed.sort((a, b) {
      final (pa, pb) = (a.$2.place, b.$2.place);
      if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
      if (pa != null && pb == null) return -1;
      if (pa == null && pb != null) return 1;
      return a.$1.compareTo(b.$1);
    });
    return [for (final (_, c) in indexed) c];
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
    _quoteDays
      ..clear()
      ..addAll(fresh._quoteDays);
    _day = fresh.today;
    _replay(lenient: true);
    notifyListeners();
  }

  void toggleHidden() {
    _hidden = !_hidden;
    _signal();
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
  List<Trashed> trash,
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
