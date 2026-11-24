import 'package:expense_tracker/src/core/ledger/cache/query_cache.dart';
import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/repositories/account_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/category_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/entry_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/holding_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/market_data_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/recurring_repository.dart';
import 'package:expense_tracker/src/core/ledger/services/balance_service.dart';
import 'package:expense_tracker/src/core/ledger/services/budget_service.dart';
import 'package:expense_tracker/src/core/ledger/services/entry_query_service.dart';
import 'package:expense_tracker/src/core/ledger/services/entry_validator.dart';
import 'package:expense_tracker/src/core/ledger/services/recurring_service.dart';
import 'package:expense_tracker/src/core/ledger/services/report_service.dart';
import 'package:expense_tracker/src/core/ledger/services/statement_service.dart';

/// The day every service test is asked on: a Sunday.
final day = DateTime.utc(2026, 10, 4);

/// An entry with what most tests leave alone filled in.
Entry entry(
  String id, {
  DateTime? date,
  EntryType type = EntryType.expense,
  int amount = 100,
  String account = 'bank',
  String category = '飲食',
  String? to,
  String merchant = '',
  List<String> tags = const [],
  String? refundOf,
  String? group,
  String? recurring,
  int installments = 1,
}) => Entry(
  id: id,
  date: date ?? day,
  type: type,
  amount: amount,
  account: account,
  category: type == EntryType.transfer ? '' : category,
  to: to,
  merchant: merchant,
  tags: tags,
  refundOf: refundOf,
  group: group,
  recurring: recurring,
  installments: installments,
);

/// The services wired on plain repositories, as the ledger wires them,
/// with no ledger in between.
final class Book {
  Book({
    List<Entry> entries = const [],
    List<Account> accounts = const [
      Account('bank', '銀行', AccountKind.bank, 1000),
      Account('cash', '現金', AccountKind.cash, 50),
    ],
    List<Category> categories = const [],
    List<Recurring> recurring = const [],
    Map<String, double> rates = const {},
    Map<String, double> sellRates = const {},
  }) : entries = EntryRepository(entries),
       accounts = AccountRepository(accounts),
       categories = CategoryRepository(categories),
       recurring = RecurringRepository(recurring),
       market = MarketDataRepository(rates: rates, sellRates: sellRates) {
    holdings = HoldingRepository(const [], moveOf: market.moveOf)
      ..replay(this.entries.all, today: today);
  }

  final EntryRepository entries;
  final AccountRepository accounts;
  final CategoryRepository categories;
  final RecurringRepository recurring;
  final MarketDataRepository market;
  late final HoldingRepository holdings;
  final cache = QueryCache();
  DateTime today = day;

  DateTime _today() => today;

  late final balances = BalanceService(
    entries: entries,
    accounts: accounts,
    holdings: holdings,
    market: market,
    cache: cache,
    today: _today,
  );
  late final statements = StatementService(
    entries: entries,
    accounts: accounts,
    balanceService: balances,
    cache: cache,
    today: _today,
  );
  late final reports = ReportService(
    entries: entries,
    accounts: accounts,
    categories: categories,
    balances: balances,
    cache: cache,
    today: _today,
  );
  late final queries = EntryQueryService(
    entries: entries,
    accounts: accounts,
    cache: cache,
    today: _today,
  );
  late final budgets = BudgetService(
    entries: entries,
    categories: categories,
    reportService: reports,
    today: _today,
  );
  late final recurringService = RecurringService(
    entries: entries,
    accounts: accounts,
    recurring: recurring,
    market: market,
    cache: cache,
    today: _today,
  );
  late final validator = EntryValidator(
    entries: entries,
    accounts: accounts,
    holdings: holdings,
    entryQueryService: queries,
    balanceService: balances,
  );
}
