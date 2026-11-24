import 'package:core/foundation_values.dart' show PublicId;
import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, ValueNotifier;

import 'amount_visibility.dart';
import 'cache/query_cache.dart';
import 'cache/topic.dart';
import 'cache/topic_notifier.dart';
import 'commands/account_commands.dart';
import 'commands/attachment_commands.dart';
import 'commands/budget_commands.dart';
import 'commands/category_commands.dart';
import 'commands/command_context.dart';
import 'commands/command_exceptions.dart';
import 'commands/entry_commands.dart';
import 'commands/holding_commands.dart';
import 'commands/recurring_commands.dart';
import 'journal/review.dart' as review;
import 'persistence/ledger_data_source.dart';
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
import 'services/balance_service.dart';
import 'services/budget_service.dart';
import 'services/entry_query_service.dart';
import 'services/entry_validator.dart';
import 'services/integrity_service.dart';
import 'services/recurring_service.dart';
import 'services/report_service.dart';
import 'services/statement_service.dart';

export 'card_cycle.dart';
export 'journal/review.dart' show NeedsReview;
export 'cache/topic.dart';
export 'commands/command_exceptions.dart';

export 'package:ledger_entries/rules.dart';

export 'services/integrity_service.dart'
    show IntegrityProblem, MissingAccount, MissingRefundOriginal, RecordKind;
export 'models/models.dart';
export 'rules/advance_rules.dart';
export 'rules/budget_rules.dart';
export 'rules/recurring_rules.dart';
// The narrow parts a model takes in place of the whole ledger
// (docs/adr/0013-models-take-what-they-use.md).
export 'commands/attachment_commands.dart' show AttachmentCommands;
export 'commands/entry_commands.dart' show EntryCommands;
export 'commands/holding_commands.dart' show HoldingCommands;
export 'commands/recurring_commands.dart' show RecurringCommands;
export 'repositories/account_repository.dart' show AccountReader;
export 'repositories/budget_repository.dart' show BudgetReader;
export 'repositories/category_repository.dart' show CategoryReader;
export 'repositories/draft_repository.dart' show DraftReader;
export 'repositories/recurring_repository.dart' show RecurringReader;
export 'services/balance_service.dart' show BalanceService, NetWorth;
export 'services/budget_service.dart' show BudgetService;
export 'services/entry_query_service.dart' show EntryQueryService;
export 'services/entry_validator.dart' show EntryValidator;
export 'services/recurring_service.dart' show RecurringService;
export 'services/statement_service.dart' show StatementService, payByOf;
export 'repositories/entry_repository.dart' show EntryReader;
export 'repositories/holding_repository.dart'
    show HoldingReader, HoldingsByStatus;
export 'repositories/market_data_repository.dart' show MarketDataReader;
export 'services/report_service.dart' show ReportService;

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
    Map<String, double> sellRates = const {},
    List<Trashed> trash = const [],
    Map<String, double> moves = const {},
    DateTime? quotedOn,
    Map<String, DateTime> quoteDays = const {},
    Map<String, String> receipts = const {},
    Map<String, String> drafts = const {},
    ReadHoldings? readHoldings,
  }) : _clock = clock ?? (() => today),
       _drafts = DraftRepository(drafts),
       _day = today,
       _receipts = ReceiptRepository(receipts),
       _market = MarketDataRepository(
         rates: rates,
         sellRates: sellRates,
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
    _holdings = HoldingRepository(
      holdings,
      moveOf: _market.moveOf,
      quoteDayOf: (code) => _market.quoteDays[code] ?? _market.quotedOn,
    );
    // Worked out on the book's worker as it opened, else here.
    if (readHoldings != null) {
      _holdings.adopt(readHoldings);
    } else {
      _holdings.replay(_entries.all, today: today, lenient: true);
    }
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
    // A trade an old book dated later joins the holdings on its day.
    _holdings.replay(_entries.all, today: now, lenient: true);
    // What was worked out for yesterday, such as the last statement,
    // is worked out again.
    notifyListeners();
  }

  /// Where changes are kept; none in the preview, which forgets them.
  final LedgerDataSource? dataSource;

  /// The last change the [data source] refused, for the screens to report.
  final problem = ValueNotifier<LedgerProblem?>(null);

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

  /// The forms put aside in the composer, kept across a restart.
  final DraftRepository _drafts;

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
  Account account(String id) => _accounts.resolve(id);

  Category category(String name) => _categories.byName(name);

  Holding? holding(String code) => _holdings.byCode(code);

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

  /// Throws away what rests on [topics], and only that: a budget changed
  /// leaves every statement and balance worked out.
  void _forget(Set<Topic> topics) {
    _topics.count(topics);
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

  /// Whether every change made so far is kept: waits for [settled], and
  /// is false when the data source refused any change meanwhile (the book
  /// is then read back, without it). A book with no data source keeps
  /// nothing, and has nothing refused.
  Future<bool> keptAll() async {
    final writes = _writes;
    if (writes == null) return true;
    final before = writes.refused;
    await writes.settled;
    return writes.refused == before;
  }

  void _keep(WriteBatch batch) => _writes?.enqueue(batch);

  // What is worked out from the records, and what writes them: built on
  // first use, all on the same repositories and cache.

  late final balanceService = BalanceService(
    entries: _entries,
    accounts: _accounts,
    holdings: _holdings,
    market: _market,
    cache: _cache,
    today: _clock,
  );
  late final statementService = StatementService(
    entries: _entries,
    accounts: _accounts,
    balanceService: balanceService,
    cache: _cache,
    today: _clock,
  );
  late final reportService = ReportService(
    entries: _entries,
    accounts: _accounts,
    categories: _categories,
    cache: _cache,
    today: _clock,
  );
  late final entryQueryService = EntryQueryService(
    entries: _entries,
    accounts: _accounts,
    cache: _cache,
    today: _clock,
  );
  late final budgetService = BudgetService(
    entries: _entries,
    reportService: reportService,
    today: _clock,
  );
  late final recurringService = RecurringService(
    entries: _entries,
    accounts: _accounts,
    recurring: _recurring,
    market: _market,
    cache: _cache,
    today: _clock,
  );
  late final integrityService = IntegrityService(
    entries: _entries,
    accounts: _accounts,
    recurring: _recurring,
    trash: _trash,
  );
  late final entryValidator = EntryValidator(
    entries: _entries,
    accounts: _accounts,
    holdings: _holdings,
    entryQueryService: entryQueryService,
    balanceService: balanceService,
    today: _clock,
  );

  late final CommandContext _context = _LedgerContext(this);

  late final entryCommands = EntryCommands(
    context: _context,
    entryRepository: _entries,
    accountRepository: _accounts,
    categoryRepository: _categories,
    holdingRepository: _holdings,
    recurringRepository: _recurring,
    budgetRepository: _budgets,
    trashRepository: _trash,
    receiptRepository: _receipts,
    recurringService: recurringService,
    entryQueryService: entryQueryService,
    entryValidator: entryValidator,
  );
  late final accountCommands = AccountCommands(
    context: _context,
    accountRepository: _accounts,
    entryRepository: _entries,
    trashRepository: _trash,
    recurringRepository: _recurring,
    balanceService: balanceService,
  );
  late final categoryCommands = CategoryCommands(
    context: _context,
    categoryRepository: _categories,
    entryRepository: _entries,
    trashRepository: _trash,
    recurringRepository: _recurring,
    budgetRepository: _budgets,
  );
  late final budgetCommands = BudgetCommands(
    context: _context,
    budgetRepository: _budgets,
  );
  late final recurringCommands = RecurringCommands(
    context: _context,
    recurringRepository: _recurring,
    entryRepository: _entries,
    accounts: _accounts,
    recurringService: recurringService,
    entryCommands: entryCommands,
    entryValidator: entryValidator,
  );
  late final holdingCommands = HoldingCommands(
    context: _context,
    marketRepository: _market,
    holdingRepository: _holdings,
    entryRepository: _entries,
  );
  late final attachmentCommands = AttachmentCommands(
    context: _context,
    receiptRepository: _receipts,
    draftRepository: _drafts,
  );

  /// The records in an old shape the person should look at (decision
  /// D47): each kept with today's figures, none changed; for a screen to
  /// list, so they can be put right by hand.
  List<review.NeedsReview> recordsNeedingReview() =>
      review.recordsNeedingReview(
        // Exception to as-of-today: a record to put right is one whatever
        // its day.
        entries: _entries.all,
        accounts: _accounts.all,
        categories: _categories.all,
        leftOut: _holdings.leftOut,
      );

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
      // Exception to as-of-today: a reload copies every entry.
      ..addAll(fresh._entries.all);
    _holdings.replaceStart(fresh._holdings.start);
    _budgets.replaceWith(fresh._budgets.all);
    _recurring.replaceWith(fresh._recurring.all);
    _trash.replaceWith(fresh._trash.all);
    _receipts.replaceWith(fresh._receipts);
    _drafts.replaceWith(fresh._drafts);
    _market.replaceWith(fresh._market);
    _day = fresh.today;
    _holdings.replay(_entries.all, today: today, lenient: true);
    notifyListeners();
  }
}

/// The ledger as its commands see it.
final class _LedgerContext implements CommandContext {
  _LedgerContext(this._ledger);

  final Ledger _ledger;

  @override
  DateTime get today => _ledger.today;

  @override
  ValueNotifier<LedgerProblem?> get problem => _ledger.problem;

  @override
  void report(LedgerProblem refused) => _ledger.problem.value = refused;

  @override
  String newId() => _ledger.newId();

  @override
  void changed(Set<Topic> topics) => _ledger._changed(topics);

  @override
  void forget(Set<Topic> topics) => _ledger._forget(topics);

  @override
  void signal() => _ledger._signal();

  @override
  void keep(WriteBatch batch) => _ledger._keep(batch);
}
