// A small ledger for the baseline tests: no data source, no demo data, so
// every figure a test reads comes from the few records it writes itself.
import 'package:expense_tracker/src/core/ledger/ledger.dart';

/// Midnight UTC of the given day.
DateTime day(int year, int month, int date) => DateTime.utc(year, month, date);

/// A ledger of exactly the given records, "today" being [today].
Ledger ledgerOf({
  required DateTime today,
  List<Account> accounts = const [Account('bank', '銀行', AccountKind.bank, 0)],
  List<Entry> entries = const [],
  List<Category> categories = const [],
  List<Budget> budgets = const [],
  List<Recurring> recurring = const [],
  Map<String, double> rates = const {},
  DateTime Function()? clock,
}) => Ledger(
  today: today,
  clock: clock,
  accounts: accounts,
  categories: categories,
  entries: entries,
  holdings: const [],
  budgets: budgets,
  recurring: recurring,
  rates: rates,
);

/// One entry written out in full.
Entry entryOf(
  String id,
  DateTime date,
  EntryType type,
  int amount,
  String account, {
  String category = '',
  String? to,
  String? holding,
  int shares = 0,
  int fee = 0,
  int tax = 0,
  int installments = 0,
  bool split = false,
  bool average = false,
  int? home,
  int? received,
  String? refundOf,
  List<(String, int)> parts = const [],
  String merchant = '',
  String note = '',
  List<String> tags = const [],
}) => Entry(
  id: id,
  date: date,
  type: type,
  amount: amount,
  account: account,
  category: category,
  to: to,
  holding: holding,
  shares: shares,
  fee: fee,
  tax: tax,
  installments: installments,
  split: split,
  average: average,
  home: home,
  received: received,
  refundOf: refundOf,
  parts: parts,
  merchant: merchant,
  note: note,
  tags: tags,
);
