import 'dart:convert';
import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/book_migrations.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

// The kept book of awkward shapes (test/fixtures/journal/awkward_book.json
// is these records as the app writes them): one of each shape that
// fits the journal as it is, and one of each old shape that does not.

DateTime day(int m, int d, [int y = 2026]) => DateTime.utc(y, m, d);

Entry entry(
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
);

final awkwardAccounts = [
  const Account('bank', '銀行', AccountKind.bank, 500000),
  const Account('cash', '現金', AccountKind.cash, 2000),
  const Account('wallet', '悠遊卡', AccountKind.wallet, 300),
  const Account('ann', '阿安', AccountKind.receivable, 0),
  const Account('usd', '美元', AccountKind.bank, 100000, currency: 'USD'),
  const Account('jpy', '日圓', AccountKind.bank, 0, currency: 'JPY'),
  const Account('loan', '房貸', AccountKind.loan, -1000000),
  const Account('side', '私房錢', AccountKind.cash, 9000, inNetWorth: false),
  Account(
    'card',
    '信用卡',
    AccountKind.card,
    -1200,
    closingDay: 20,
    dueDay: 5,
    // The September statement closed two days early.
    closes: {day(9, 20): day(9, 18)},
  ),
  const Account(
    'usdcard',
    '美元卡',
    AccountKind.card,
    0,
    closingDay: 10,
    dueDay: 25,
    currency: 'USD',
  ),
];

List<Category> awkwardCategories() => [
  Category('飲食', 'food', 0xFF000000, id: 'c-food'),
  Category('居家', 'home', 0xFF000000, id: 'c-home'),
  Category('其他支出', 'other', 0xFF000000, id: 'c-other'),
  Category('薪水', 'salary', 0xFF000000, id: 'c-pay', income: true),
  Category('股息收入', 'dividend', 0xFF000000, id: 'c-div', income: true),
];

/// The shapes that post with every figure the same.
final fitting = [
  entry('pay', day(9, 1), EntryType.income, 52000, 'bank', category: '薪水'),
  entry(
    'split',
    day(9, 2),
    EntryType.expense,
    900,
    'bank',
    category: '飲食',
    parts: [('飲食', 600), ('居家', 300)],
  ),
  entry(
    'fee',
    day(9, 3),
    EntryType.transfer,
    1000,
    'bank',
    to: 'cash',
    fee: 15,
  ),
  entry('lend', day(9, 3), EntryType.transfer, 300, 'bank', to: 'ann'),
  entry('topup', day(9, 4), EntryType.transfer, 500, 'cash', to: 'wallet'),
  entry('repay', day(9, 5), EntryType.transfer, 5059, 'bank', to: 'loan'),
  entry('hidden', day(9, 5), EntryType.expense, 100, 'side', category: '飲食'),
  entry('shoes', day(9, 6), EntryType.expense, 3000, 'card', category: '居家'),
  entry(
    'back',
    day(9, 9),
    EntryType.income,
    1000,
    'card',
    category: '居家',
    refundOf: 'shoes',
  ),
  // Bought before the moved September close, and after it.
  entry(
    'tv',
    day(9, 14),
    EntryType.expense,
    10001,
    'card',
    category: '居家',
    installments: 3,
  ),
  entry(
    'sofa',
    day(9, 19),
    EntryType.expense,
    24000,
    'card',
    category: '居家',
    installments: 12,
  ),
  entry('payCard', day(9, 25), EntryType.transfer, 2000, 'bank', to: 'card'),
  entry(
    'fx',
    day(9, 8),
    EntryType.transfer,
    32100,
    'bank',
    to: 'usd',
    received: 100000,
  ),
  entry(
    'meal-usd',
    day(9, 10),
    EntryType.expense,
    2000,
    'usd',
    category: '飲食',
    home: 650,
  ),
  entry(
    'meal-usd-back',
    day(9, 12),
    EntryType.income,
    500,
    'usd',
    category: '飲食',
    home: 160,
    refundOf: 'meal-usd',
  ),
  entry(
    'gig-usd',
    day(9, 11),
    EntryType.income,
    5000,
    'usd',
    category: '薪水',
    home: 1600,
  ),
  // A US$ card in instalments with its worth at home: both amendments.
  entry(
    'usd-tv',
    day(9, 15),
    EntryType.expense,
    30000,
    'usdcard',
    category: '居家',
    installments: 3,
    home: 9600,
  ),
  entry(
    'b0',
    day(9, 1),
    EntryType.buy,
    120000,
    'bank',
    holding: '0050',
    shares: 1000,
  ),
  entry(
    'b1',
    day(9, 4),
    EntryType.buy,
    60000,
    'bank',
    holding: '2330',
    shares: 100,
    fee: 85,
  ),
  entry(
    'b2',
    day(9, 7),
    EntryType.buy,
    65000,
    'bank',
    holding: '2330',
    shares: 100,
    fee: 92,
  ),
  entry(
    's1',
    day(9, 10),
    EntryType.sell,
    105000,
    'bank',
    holding: '2330',
    shares: 150,
    fee: 149,
    tax: 315,
  ),
  entry(
    'b3',
    day(9, 12),
    EntryType.buy,
    33333,
    'bank',
    holding: '2330',
    shares: 70,
    fee: 47,
  ),
  // Average cost over an odd number of shares, for the rounding.
  entry(
    's2',
    day(9, 15),
    EntryType.sell,
    40000,
    'bank',
    holding: '2330',
    shares: 33,
    fee: 57,
    tax: 120,
    average: true,
  ),
  entry(
    's3',
    day(9, 16),
    EntryType.sell,
    20000,
    'bank',
    holding: '2330',
    shares: 17,
    fee: 28,
    tax: 60,
  ),
  entry(
    'd1',
    day(9, 26),
    EntryType.dividend,
    4500,
    'bank',
    holding: '0050',
    tax: 95,
    category: '股息收入',
  ),
  entry(
    's4',
    day(9, 27),
    EntryType.sell,
    80000,
    'bank',
    holding: '0050',
    shares: 400,
    fee: 114,
    tax: 80,
  ),
  // Shares given to a holding: 100 more of 0050, at no cost.
  entry(
    'stock',
    day(9, 28),
    EntryType.dividend,
    0,
    'bank',
    holding: '0050',
    shares: 100,
    category: '股息收入',
  ),
  entry(
    's5',
    day(9, 29),
    EntryType.sell,
    30000,
    'bank',
    holding: '0050',
    shares: 150,
    fee: 42,
    tax: 30,
  ),
  // A split of 0050, 2 for 1 (550 more), then a sale across the lots.
  entry(
    'split2',
    day(9, 30),
    EntryType.dividend,
    0,
    'bank',
    holding: '0050',
    shares: 550,
    split: true,
  ),
  entry(
    's6',
    day(10, 1),
    EntryType.sell,
    9000,
    'bank',
    holding: '0050',
    shares: 101,
    fee: 20,
    tax: 9,
  ),
  // A capital reduction of 2330: 20 of the 70 shares back, 5,000 returned.
  entry(
    'reduce',
    day(10, 1),
    EntryType.dividend,
    5000,
    'bank',
    holding: '2330',
    shares: -20,
  ),
  // A stock dividend that leaves a fraction: 7 for every 50 held.
  entry(
    'odd-lot',
    day(10, 2),
    EntryType.dividend,
    0,
    'bank',
    holding: '2330',
    shares: 7,
  ),
  entry(
    's7',
    day(10, 3),
    EntryType.sell,
    9000,
    'bank',
    holding: '2330',
    shares: 13,
    fee: 20,
    tax: 27,
  ),
  // A reduction taking every share and returning less than they cost.
  entry(
    'wipe',
    day(10, 4),
    EntryType.dividend,
    1000,
    'bank',
    holding: '2330',
    shares: -44,
  ),
];

/// One record of each old shape (OldShape), kept as an older version or
/// an import would have written it.
final oldShapes = [
  entry('usd-bare', day(9, 13), EntryType.expense, 1500, 'usd', category: '飲食'),
  entry('jpy-bare', day(9, 14), EntryType.transfer, 5000, 'bank', to: 'jpy'),
  entry(
    'under-food',
    day(9, 16),
    EntryType.income,
    700,
    'bank',
    category: '飲食',
  ),
  entry(
    'under-pay',
    day(9, 17),
    EntryType.expense,
    300,
    'bank',
    category: '薪水',
  ),
  entry(
    'usd-fee',
    day(9, 18),
    EntryType.transfer,
    1000,
    'usd',
    to: 'bank',
    fee: 5,
    received: 32000,
  ),
  entry(
    'oversold',
    day(10, 2),
    EntryType.sell,
    50000,
    'bank',
    holding: '0050',
    shares: 9999,
  ),
  entry('no-stock', day(9, 20), EntryType.buy, 800, 'bank', shares: 1),
  entry('usd-div', day(9, 21), EntryType.dividend, 300, 'usd', holding: '0050'),
  entry('gone', day(9, 22), EntryType.expense, 250, 'closed', category: '飲食'),
  entry(
    'bank-instal',
    day(9, 23),
    EntryType.expense,
    3000,
    'bank',
    category: '居家',
    installments: 3,
  ),
];

/// The kept book of awkward shapes: written once from awkward_book.dart
/// (`MAKE_FIXTURES=1`), then read as it is, as a kept book of an older
/// version would be.
const keptFile = 'test/fixtures/journal/awkward_book.json';
final keptClock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 4, 4)));

/// The kept book written into a new store in [scratch], as it is.
EncryptedDatabase keptStore(Directory scratch) {
  final rows =
      (jsonDecode(File(keptFile).readAsStringSync()) as Map<String, Object?>)
          .map(
            (k, v) => MapEntry(k, [for (final r in v! as List) r as String]),
          );
  final store = EncryptedDatabase.open(
    File('${scratch.path}/kept.db'),
    StorageKey.random(),
  );
  addTearDown(store.close);
  store.write((w) {
    for (final MapEntry(key: shelf, value: bodies) in rows.entries) {
      for (final body in bodies) {
        final id = (jsonDecode(body) as Map<String, Object?>)['id']! as String;
        w.put(shelf, id, body);
      }
    }
    markCurrent(w);
  });
  return store;
}

/// The kept book opened as the app opens a book.
Future<Ledger> openKept(Directory scratch) =>
    SqlLedgerDataSource(keptStore(scratch), clock: keptClock).load();
