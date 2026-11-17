import 'dart:collection' show UnmodifiableListView;
import 'dart:math';

import 'package:core/foundation_values.dart'
    show BusinessDate, Currency, PublicId;
import 'package:domain/credit_cards.dart' show CardScheduleChange;
import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, ValueNotifier;

import '../text/amounts.dart';
import 'amount_visibility.dart';
import 'attachments.dart';
import 'cache/query_cache.dart';
import 'cache/topic.dart';
import 'cache/topic_notifier.dart';
import 'card_cycle.dart';
import 'persistence/ledger_data_source.dart';
import 'persistence/write_queue.dart';
import 'portfolio.dart';
import 'repositories/budget_repository.dart';
import 'repositories/entry_repository.dart';
import 'models/models.dart';

export 'card_cycle.dart';
export 'cache/topic.dart';
export 'models/models.dart';

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
    this.dataSource,
    Map<String, double> rates = const {},
    List<Trashed> trash = const [],
    Map<String, double> moves = const {},
    this._quotedOn,
    Map<String, DateTime> quoteDays = const {},
    Map<String, String> receipts = const {},
    Map<String, String> drafts = const {},
  }) : _clock = clock ?? (() => today),
       _drafts = Drafts(drafts),
       _day = today,
       _quoteDays = {...quoteDays},
       _receipts = Receipts(receipts),
       _rates = {...rates},
       _moves = {...moves},
       _trash = [...trash],
       _accounts = [...accounts],
       _categories = _placed(categories),
       _entries = EntryRepository(entries),
       _startHoldings = [...holdings],
       _budgets = BudgetRepository(budgets),
       _recurring = [...recurring] {
    _replay(lenient: true);
    amounts.addListener(_signal);
    final source = dataSource;
    if (source != null) {
      _writes = WriteQueue(source, problem: problem, onReloaded: _adopt);
    }
  }

  @override
  void dispose() {
    amounts.dispose();
    super.dispose();
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
  final LedgerDataSource? dataSource;

  /// The last change the [data source] refused, for the screens to report.
  final problem = ValueNotifier<Object?>(null);

  final List<Account> _accounts;
  final List<Category> _categories;
  final EntryRepository _entries;
  final List<Holding> _startHoldings;
  final BudgetRepository _budgets;
  final List<Recurring> _recurring;

  /// Entries deleted lately, newest first, until restored.
  final List<Trashed> _trash;

  /// The photo of each entry's receipt, by entry id: a file name the
  /// phone keeps.
  final Receipts _receipts;

  /// The receipt photo of the entry with [id]; null when none.
  String? receiptOf(String id) => _receipts.of(id);

  /// Every receipt photo an entry keeps, deleted entries' included.
  Set<String> get receiptFiles => {
    ..._receipts.files,
    // A form put aside keeps the photo chosen for it.
    ..._drafts.receipts,
  };

  /// The forms put aside in the composer, kept across a restart.
  final Drafts _drafts;

  String? draft(String tab) => _drafts.of(tab);

  /// Keeps the form put aside on [tab], or clears it when [json] is null.
  void setDraft(String tab, String? json) {
    if (!_drafts.set(tab, json)) return;
    _keep(WriteBatch(drafts: {tab: json}));
  }

  /// Gives the entry with [id] the receipt photo [file], or takes its
  /// photo away when null.
  void setReceipt(String id, String? file) {
    if (!_receipts.set(id, file)) return;
    _signal();
    _keep(WriteBatch(receipts: {id: file}));
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

  /// The 隱藏金額 switch: amounts written as dots. Its changes reach the
  /// screens as a change of how amounts are shown, which leaves every sum
  /// worked out as it was.
  final amounts = AmountVisibility();

  List<Account> get accounts => List.unmodifiable(_accounts);
  List<Category> get categories => List.unmodifiable(_categories);
  List<Holding> get holdings => UnmodifiableListView(_holdings);
  List<Budget> get budgets => _budgets.all;
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
  List<Entry> entriesIn(int year, int month) => _entries.inMonth(year, month);

  /// What the screens ask for again and again, worked out once per change:
  /// balances by account and day, accounts by id.
  Map<String, _Running>? _running;
  final _balances = <(String, DateTime), int>{};
  Map<String, Account>? _accountIndex;

  /// Answers worked out once per change of what they rest on.
  final _cache = QueryCache();

  /// Counts and announces the changes of each topic.
  final _topics = TopicNotifier();

  /// Moves on with every change of what the sums are worked out from, so
  /// a screen that keeps sums of its own knows when to work them out
  /// again; hiding the amounts leaves it.
  int get revision => _topics.revision;

  /// How many times [topic] has changed, for a screen that keeps sums
  /// resting on some topics only.
  int revisionOf(Topic topic) => _topics.revisionOf(topic);

  /// What [make] works out, once per change of the [on] topics for each
  /// [key]. A key should hold every argument the answer depends on, the
  /// day included; [on] is every topic it reads.
  T _remember<T>(Object key, T Function() make, {Set<Topic> on = Topic.all}) =>
      _cache.remember(key, make, reads: on);

  Map<String, Category>? _categoryIndex;

  /// Throws away what rests on [topics], and only that: a budget changed
  /// leaves every statement and balance worked out.
  void _forget(Set<Topic> topics) {
    _topics.count(topics);
    if (topics.contains(Topic.categories)) _categoryIndex = null;
    if (topics.contains(Topic.entries) || topics.contains(Topic.accounts)) {
      _running = null;
      _balances.clear();
    }
    if (topics.contains(Topic.accounts)) _accountIndex = null;
    if (topics.contains(Topic.entries) || topics.contains(Topic.market)) {
      _moved = null;
    }
    _cache.forget(topics);
  }

  /// Tells the screens of a change of every topic.
  @override
  void notifyListeners() => _changed(Topic.all);

  /// Tells the screens [topics] changed, after throwing away what rests on
  /// them; those listening to [watch] hear only of the topics they asked
  /// for.
  void _changed(Set<Topic> topics) {
    _forget(topics);
    super.notifyListeners();
    _topics.announce(topics);
  }

  /// Tells the screens of a change that leaves every sum as it was, such
  /// as hiding the amounts: nothing worked out is thrown away.
  void _signal() {
    super.notifyListeners();
    _topics.announce(const {Topic.display});
  }

  /// Changes of [topics] only, and of how amounts are shown: for a screen
  /// that need not be built again when, say, a budget changes.
  Listenable watch(Set<Topic> topics) => _topics.watch(topics);

  /// Every entry, in the order written; the list cannot be changed.
  List<Entry> get entries => UnmodifiableListView(_entries);

  // Changes.

  String newId() => PublicId.generate().value;

  /// Hands the changes to the data source in turn; none without one.
  WriteQueue? _writes;

  /// Done once every change so far has reached the data source.
  Future<void> get settled => _writes?.settled ?? Future<void>.value();

  void _keep(WriteBatch batch) => _writes?.enqueue(batch);

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
    _changed(const {Topic.market});
  }

  /// What a change of several records left different: every record not
  /// the very one it was before is kept, and those gone are dropped.
  WriteBatch _since(_Before before) {
    List<T> changed<T>(List<T> was, List<T> now, String Function(T) key) {
      final old = {for (final item in was) key(item): item};
      return [
        for (final item in now)
          if (!identical(old[key(item)], item)) item,
      ];
    }

    List<(Collection, String)> gone<T>(
      Collection collection,
      List<T> was,
      List<T> now,
      String Function(T) key,
    ) {
      final kept = {for (final item in now) key(item)};
      return [
        for (final item in was)
          if (!kept.contains(key(item))) (collection, key(item)),
      ];
    }

    String entryKey(Entry e) => e.id;
    String categoryKey(Category c) => c.id;
    String budgetKey(Budget b) => b.category;
    String recurringKey(Recurring r) => r.id;
    return WriteBatch(
      entries: changed(before.entries, _entries, entryKey),
      categories: changed(before.categories, _categories, categoryKey),
      budgets: changed(before.budgets, _budgets.all, budgetKey),
      recurring: changed(before.recurring, _recurring, recurringKey),
      // Entries in the trash follow a rename or a merge too.
      trash: changed(before.trash, _trash, (t) => t.entry.id),
      dropped: [
        ...gone(Collection.entry, before.entries, _entries, entryKey),
        ...gone(
          Collection.category,
          before.categories,
          _categories,
          categoryKey,
        ),
        ...gone(Collection.budget, before.budgets, _budgets.all, budgetKey),
        ...gone(
          Collection.recurring,
          before.recurring,
          _recurring,
          recurringKey,
        ),
      ],
    );
  }

  _Before get _before => (
    entries: List.of(_entries),
    categories: List.of(_categories),
    budgets: _budgets.all,
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
    amounts.reset();
    notifyListeners();
  }

  /// Takes the contents of [fresh], as reloaded from the [data source].
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
    _budgets.replaceWith(fresh._budgets.all);
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
    _receipts.replaceWith(fresh._receipts);
    _drafts.replaceWith(fresh._drafts);
    _quotedOn = fresh._quotedOn;
    _quoteDays
      ..clear()
      ..addAll(fresh._quoteDays);
    _day = fresh.today;
    _replay(lenient: true);
    notifyListeners();
  }
}

/// One account's entries in date order with the balance change up to each
/// of them, so a balance on any day is one search. Instalment purchases
/// are kept apart: what they have billed depends on the day asked about.
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
