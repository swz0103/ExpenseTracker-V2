import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/services/budget_service.dart';
import 'package:expense_tracker/src/features/accounts/model/card_summary.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/book.dart';

// As of today (D25): an entry dated tomorrow is 預定 and changes no figure
// any read method shows today. Each kind of entry below is added, dated
// tomorrow, to the same book, and every read method is asked again: the
// answer must be the one it gave without it. Review 11 found the filter
// could be taken out of several of these with no test failing.
//
// Left out on purpose, as their own documented exceptions: the account's
// entry list (BalanceService.entriesOf shows 預定 entries, marked), the
// tag and merchant names offered to pick from (ReportService.tags,
// EntryQueryService.merchants), and a balance asked for a later day.

const _card = Account(
  'card',
  '卡',
  AccountKind.card,
  0,
  closingDay: 25,
  dueDay: 10,
  limit: 50000,
);

final _tomorrow = DateTime.utc(2026, 10, 5);

List<Entry> _base() => [
  entry(
    'lunch',
    amount: 120,
    date: DateTime.utc(2026, 10, 1),
    merchant: '麵店',
    tags: ['日常'],
  ),
  entry(
    'pay',
    type: EntryType.income,
    amount: 30000,
    date: DateTime.utc(2026, 10, 2),
    category: '薪資收入',
  ),
  entry(
    'billed',
    account: 'card',
    amount: 800,
    date: DateTime.utc(2026, 9, 20),
  ),
  entry('since', account: 'card', amount: 300, date: DateTime.utc(2026, 10, 2)),
  entry(
    'plan',
    account: 'card',
    amount: 3000,
    installments: 3,
    date: DateTime.utc(2026, 9, 1),
  ),
  entry(
    'lend',
    type: EntryType.transfer,
    amount: 500,
    to: 'amy',
    date: DateTime.utc(2026, 9, 15),
  ),
  entry(
    'bus',
    account: 'cash',
    amount: 30,
    category: '交通',
    date: DateTime.utc(2026, 9, 28),
    merchant: '客運',
  ),
];

/// Each kind of entry, dated tomorrow.
final _planned = <String, Entry>{
  'a spending with a merchant and a tag': entry(
    'p',
    date: _tomorrow,
    amount: 777,
    merchant: '麵店',
    tags: ['日常', '旅行'],
  ),
  'an income': entry(
    'p',
    type: EntryType.income,
    amount: 5000,
    date: _tomorrow,
    category: '薪資收入',
  ),
  'a transfer between own accounts': entry(
    'p',
    type: EntryType.transfer,
    amount: 400,
    to: 'cash',
    date: _tomorrow,
  ),
  'a card spending': entry(
    'p',
    account: 'card',
    amount: 650,
    date: _tomorrow,
    merchant: '超市',
  ),
  'a card payment': entry(
    'p',
    type: EntryType.transfer,
    amount: 800,
    to: 'card',
    date: _tomorrow,
  ),
  'a refund of a card spending': entry(
    'p',
    type: EntryType.income,
    account: 'card',
    amount: 300,
    refundOf: 'since',
    date: _tomorrow,
  ),
  'a refund of an instalment purchase': entry(
    'p',
    type: EntryType.income,
    account: 'card',
    amount: 3000,
    refundOf: 'plan',
    date: _tomorrow,
  ),
  'a purchase in instalments': entry(
    'p',
    account: 'card',
    amount: 1200,
    installments: 6,
    date: _tomorrow,
  ),
  'money lent': entry(
    'p',
    type: EntryType.transfer,
    amount: 900,
    to: 'amy',
    date: _tomorrow,
  ),
  'money paid back': entry(
    'p',
    type: EntryType.transfer,
    account: 'amy',
    amount: 200,
    to: 'bank',
    date: _tomorrow,
  ),
  'a cashback credit': Entry(
    id: 'p',
    date: _tomorrow,
    type: EntryType.income,
    amount: 88,
    account: 'card',
    category: '其他收入',
    mark: EntryMark.reward,
  ),
};

Book _book(List<Entry> entries) => Book(
  accounts: const [
    Account('bank', '銀行', AccountKind.bank, 10000),
    Account('cash', '現金', AccountKind.cash, 50),
    _card,
    Account('amy', '阿美', AccountKind.receivable, 0),
  ],
  categories: [
    Category('飲食', 'food', 0),
    Category('交通', 'bus', 0),
    Category('薪資收入', 'salary', 0, income: true),
  ],
  entries: entries,
);

CardSummary _summary(Book b) => CardSummary.of(
  _card,
  statements: b.statements,
  balances: b.balances,
  entries: b.entries,
  accounts: b.accounts,
  today: b.today,
);

/// Every read method, by name, as a value that compares by content.
final _readers = <String, Object? Function(Book)>{
  // ReportService.
  'income': (b) => b.reports.income(2026, 10),
  'expense': (b) => b.reports.expense(2026, 10),
  'expense of the card': (b) => b.reports.expense(2026, 10, account: 'card'),
  'totalsOf': (b) => b.reports.totalsOf(b.entries.all),
  'dividends': (b) => b.reports.dividends(2026, 10),
  'spentOn today': (b) => b.reports.spentOn(day),
  'spentOn tomorrow': (b) => b.reports.spentOn(_tomorrow),
  'totalsBetween': (b) => b.reports.totalsBetween(
    DateTime.utc(2026, 9),
    DateTime.utc(2026, 10, 31),
  ),
  'spendingBetween': (b) => b.reports.spendingBetween(
    DateTime.utc(2026, 9),
    DateTime.utc(2026, 10, 31),
  ),
  'merchantsBetween': (b) => b.reports.merchantsBetween(
    DateTime.utc(2026, 9),
    DateTime.utc(2026, 10, 31),
  ),
  'tagsBetween': (b) =>
      b.reports.tagsBetween(DateTime.utc(2026, 9), DateTime.utc(2026, 10, 31)),
  'owedBy': (b) => [for (final (e, n) in b.reports.owedBy('amy')) (e.id, n)],
  'tagStats': (b) => b.reports.tagStats,
  'merchantStats': (b) => b.reports.merchantStats,
  'categoriesByUse': (b) => b.reports.categoriesByUse(income: false),
  'categoriesByUse income': (b) => b.reports.categoriesByUse(income: true),
  // BalanceService.
  'balance': (b) => [
    for (final a in const ['bank', 'cash', 'card', 'amy'])
      b.balances.balance(a),
  ],
  'flowOf': (b) => [
    for (final a in const ['bank', 'cash', 'card', 'amy'])
      b.balances.flowOf(a, day),
  ],
  'weeklyChanges': (b) => [
    for (final a in const ['bank', 'cash', 'card', 'amy'])
      b.balances.weeklyChanges(a),
  ],
  'netWorth': (b) {
    final w = b.balances.netWorth(day);
    return (w.saved, w.invested, w.lent, w.owed);
  },
  'assets, cardDebt, loanDebt': (b) =>
      (b.balances.assets, b.balances.cardDebt, b.balances.loanDebt),
  'stillToBill': (b) => b.balances.stillToBill(b.entries.byId('plan')!),
  // StatementService.
  'statement': (b) => b.statements.statement(_card),
  'statementDue': (b) => b.statements.statementDue(_card),
  'billStatus': (b) => b.statements.billStatus(_card),
  'unbilled': (b) => [for (final e in b.statements.unbilled(_card)) e.id],
  'instalmentsOn': (b) => [
    for (final e in b.statements.instalmentsOn(_card)) e.id,
  ],
  // BudgetService.
  'spentOnTag': (b) => b.budgets.spentOnTag('日常', 2026, 10),
  'spentAgainst': (b) => [
    for (final budget in const [
      Budget(allSpending, 20000),
      Budget('飲食', 5000),
      Budget('#日常', 1000),
    ])
      b.budgets.spentAgainst(budget, 2026, 10),
  ],
  'forecast': (b) => b.budgets.forecast(b.reports.expense(2026, 10), 2026, 10),
  'pace': (b) {
    final pace = b.budgets.pace(b.reports.expense(2026, 10), 20000, 2026, 10);
    return switch (pace) {
      CurrentPace(:final daysLeft, :final perDay, :final forecast) => (
        daysLeft,
        perDay,
        forecast,
      ),
      PastPace(:final days, :final perDay, :final saved) => (
        days,
        perDay,
        saved,
      ),
    };
  },
  'allowance next month': (b) =>
      b.budgets.allowance(const Budget('飲食', 5000, carry: true), 2026, 11),
  // EntryQueryService.
  'lastUsedOn': (b) => b.queries.lastUsedOn,
  'lastAt': (b) => b.queries.lastAt('麵店')?.id,
  'usual': (b) => [for (final e in b.queries.usual()) e.id],
  'usual income': (b) => [for (final e in b.queries.usual(income: true)) e.id],
  'usualTransfers': (b) => [for (final e in b.queries.usualTransfers()) e.id],
  // The card's page.
  'card summary': (b) {
    final s = _summary(b);
    // A list, not a record: a record holding a list compares it by
    // identity.
    return [
      s.owed,
      s.spentSince,
      [for (final e in s.unbilled) e.id],
      s.pending,
      s.debt,
      s.available,
      s.usedPercent,
    ];
  },
  'card marks': (b) {
    final s = _summary(b);
    return (
      s.markedThisYear(EntryMark.reward),
      s.markedSinceClose(EntryMark.reward),
    );
  },
};

void main() {
  test('the book without the planned entries reads what it should', () {
    final b = _book(_base());
    // 10000 - 120 + 30000 - 500 = 39380.
    expect(b.balances.balance('bank'), 39380);
    // Spent in October: the lunch 120 + the card's 300 = 420 (the
    // instalment purchase counts whole in September, on its day).
    expect(b.reports.expense(2026, 10), 420);
  });

  for (final MapEntry(key: kind, value: planned) in _planned.entries) {
    group('$kind dated tomorrow', () {
      final without = _book(_base());
      final withIt = _book([..._base(), planned]);
      for (final MapEntry(key: name, value: read) in _readers.entries) {
        test('changes no $name', () {
          expect(read(withIt), read(without));
        });
      }
      test('counts once its day comes', () {
        // The control: with the clock on tomorrow, some read method
        // answers otherwise, so the cases above are not empty.
        final later = _book([..._base(), planned])..today = _tomorrow;
        final before = _book(_base())..today = _tomorrow;
        expect([
          for (final read in _readers.values) read(later),
        ], isNot([for (final read in _readers.values) read(before)]));
      });
    });
  }
}
