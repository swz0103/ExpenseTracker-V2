import 'dart:math';

import 'package:core/foundation_values.dart' show BusinessDate, PublicId;
import 'package:domain/credit_cards.dart' show CardScheduleChange;
import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, ValueNotifier;

import '../text/amounts.dart';
import 'amount_visibility.dart';
import 'cache/query_cache.dart';
import 'cache/topic.dart';
import 'cache/topic_notifier.dart';
import 'card_cycle.dart';
import 'persistence/ledger_data_source.dart';
import 'persistence/unit_of_work.dart';
import 'persistence/write_queue.dart';
import 'repositories/account_repository.dart';
import 'repositories/budget_repository.dart';
import 'repositories/category_repository.dart';
import 'repositories/draft_repository.dart';
import 'repositories/holding_repository.dart';
import 'repositories/market_data_repository.dart';
import 'repositories/receipt_repository.dart';
import 'repositories/entry_repository.dart';
import 'repositories/recurring_repository.dart';
import 'repositories/trash_repository.dart';
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
    DateTime? quotedOn,
    Map<String, DateTime> quoteDays = const {},
    Map<String, String> receipts = const {},
    Map<String, String> drafts = const {},
  }) : _clock = clock ?? (() => today),
       _drafts = DraftRepository(drafts),
       _day = today,
       _receipts = ReceiptRepository(receipts),
       _market = MarketDataRepository(
         rates: rates,
         moves: moves,
         quotedOn: quotedOn,
         quoteDays: quoteDays,
       ),
       _trash = TrashRepository(trash),
       _accounts = AccountRepository(accounts),
       _categories = CategoryRepository(categories),
       _entries = EntryRepository(entries),
       _budgets = BudgetRepository(budgets),
       _recurring = RecurringRepository(recurring) {
    _holdings = HoldingRepository(holdings, moveOf: _market.moveOf);
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

  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final EntryRepository _entries;
  final MarketDataRepository _market;
  late final HoldingRepository _holdings;
  final BudgetRepository _budgets;
  final RecurringRepository _recurring;

  /// Entries deleted lately, newest first, until restored.
  final TrashRepository _trash;

  /// The photo of each entry's receipt, by entry id: a file name the
  /// phone keeps.
  final ReceiptRepository _receipts;

  /// Every receipt photo an entry keeps, deleted entries' included.
  Set<String> get receiptFiles => {
    ..._receipts.files,
    // A form put aside keeps the photo chosen for it.
    ..._drafts.receipts,
  };

  /// The forms put aside in the composer, kept across a restart.
  final DraftRepository _drafts;

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

  /// The 隱藏金額 switch: amounts written as dots. Its changes reach the
  /// screens as a change of how amounts are shown, which leaves every sum
  /// worked out as it was.
  final amounts = AmountVisibility();

  /// The book's records by kind, to read; the commands change them.
  AccountReader get accounts => _accounts;
  CategoryReader get categories => _categories;
  EntryReader get entries => _entries;
  HoldingReader get holdings => _holdings;
  BudgetReader get budgets => _budgets;
  RecurringReader get recurring => _recurring;
  TrashReader get trash => _trash;
  MarketDataReader get marketData => _market;
  ReceiptReader get receipts => _receipts;
  DraftReader get drafts => _drafts;

  /// The account [id]; one of that name and no balance when the book has
  /// none, as for an entry whose account was never kept.
  Account account(String id) =>
      _accounts.byId(id) ?? Account(id, id, AccountKind.bank, 0);

  Category category(String name) => _categories.byName(name);

  Holding? holding(String code) => _holdings.byCode(code);

  /// What the screens ask for again and again, worked out once per change:
  /// balances by account and day, accounts by id.
  Map<String, _Running>? _running;
  final _balances = <(String, DateTime), int>{};

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

  /// Throws away what rests on [topics], and only that: a budget changed
  /// leaves every statement and balance worked out.
  void _forget(Set<Topic> topics) {
    _topics.count(topics);
    if (topics.contains(Topic.entries) || topics.contains(Topic.accounts)) {
      _running = null;
      _balances.clear();
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
    _market.replace(
      rates: rates,
      moves: moves,
      quotedOn: quotedOn,
      quoteDays: quoteDays,
    );
    _holdings.replaceStart(holdings);
    _replay(lenient: true);
    _changed(const {Topic.market});
  }

  /// Replaces everything with the contents of [fresh], for a demo reset.
  void resetTo(Ledger fresh) {
    _adopt(fresh);
    amounts.reset();
    notifyListeners();
  }

  /// Takes the contents of [fresh], as reloaded from the [data source].
  void _adopt(Ledger fresh) {
    _accounts.replaceWith(fresh._accounts.all);
    _categories.replaceWith(fresh._categories.all);
    _entries
      ..clear()
      ..addAll(fresh._entries);
    _holdings.replaceStart(fresh._holdings.start);
    _budgets.replaceWith(fresh._budgets.all);
    _recurring.replaceWith(fresh._recurring.all);
    _trash.replaceWith(fresh._trash.all);
    _receipts.replaceWith(fresh._receipts);
    _drafts.replaceWith(fresh._drafts);
    _market.replaceWith(fresh._market);
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
