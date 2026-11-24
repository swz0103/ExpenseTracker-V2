/// D25: an ordinary entry dated after today is 預定. It is listed, marked,
/// and counted in nothing "as of today" (balances, net worth, budgets,
/// the overview's and reports' sums, a card bill) until its day comes;
/// then it counts with nothing written, at the day's rollover. Every one
/// of these asks the one predicate, `countsOn` (package ledger_entries).
library;

import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/widgets/entry_tile.dart';
import 'package:expense_tracker/src/features/entries/model/entry_details.dart';
import 'package:expense_tracker/src/features/reports/model/report.dart';
import 'package:expense_tracker/src/features/reports/model/report_period.dart';
import 'package:expense_tracker/src/features/tags/model/tag_summary.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../baseline/baseline_ledger.dart';

void main() {
  late DateTime today;
  late Ledger ledger;

  setUp(() {
    today = DateTime.utc(2026, 11, 24);
    ledger = ledgerOf(
      today: today,
      clock: () => today,
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 10000),
        // Closes on the 10th, due on the 30th.
        Account('card', '信用卡', AccountKind.card, 0, closingDay: 10, dueDay: 30),
      ],
      categories: [Category('飲食', 'food', 0xFF5C9A83)],
      budgets: const [Budget('飲食', 2000), Budget(allSpending, 10000)],
      entries: [
        entryOf(
          'lunch',
          DateTime.utc(2026, 11, 20),
          EntryType.expense,
          1000,
          'bank',
          category: '飲食',
        ),
        // Billed by the statement closing 11/10, due 11/30.
        entryOf(
          'tv',
          DateTime.utc(2026, 11, 1),
          EntryType.expense,
          5000,
          'card',
          category: '飲食',
        ),
      ],
    );
    // Two 預定 entries for 11/28, written through the commands.
    ledger.entryCommands.add(
      entryOf(
        'dinner',
        DateTime.utc(2026, 11, 28),
        EntryType.expense,
        300,
        'bank',
        category: '飲食',
      ),
    );
    ledger.entryCommands.add(
      entryOf(
        'pay',
        DateTime.utc(2026, 11, 28),
        EntryType.transfer,
        5000,
        'bank',
        category: transferCategory,
        to: 'card',
      ),
    );
  });

  Report november() => Report.of(
    ReportPeriod.of(ReportSpan.month, ledger.today),
    entries: ledger.entries,
    reports: ledger.reportService,
    balances: ledger.balanceService,
    today: ledger.today,
  );

  test('before its day a 預定 entry counts nowhere', () {
    // Balance: 10,000 - 1,000 = 9,000; the 300 and the 5,000 wait.
    expect(ledger.balanceService.balance('bank'), 9000);
    // Net worth: 9,000 in the bank less 5,000 owed on the card = 4,000.
    expect(ledger.balanceService.netWorthAt(ledger.today), 4000);
    // November's spending: 1,000 + 5,000 = 6,000, as the overview and
    // the reports read it.
    expect(ledger.reportService.expense(2026, 11), 6000);
    expect(ledger.reportService.expense(2026, 11, account: 'bank'), 1000);
    // Budgets: 飲食 has 1,000 + 5,000 = 6,000 against it, not 6,300.
    final food = ledger.budgets.all.firstWhere((b) => b.category == '飲食');
    expect(ledger.budgetService.spentAgainst(food, 2026, 11), 6000);
    // The card bill is not paid by a payment still to come: 11/30 is six
    // days away.
    expect(ledger.statementService.statementDue(ledger.account('card')), 5000);
    expect(
      ledger.statementService.billStatus(ledger.account('card')),
      BillDue(BusinessDate(2026, 11, 30), 6),
    );
  });

  test('the report keeps its 預定 entries apart', () {
    final report = november();
    expect(report.expense, 6000);
    expect([
      for (final e in report.planned) e.id,
    ], unorderedEquals(['dinner', 'pay']));
    // Only the 300 dinner is spending; the payment moves money.
    expect(report.plannedSpending, 300);
  });

  test('lists and the entry looked at say 預定', () {
    final dinner = ledger.entries.byId('dinner')!;
    expect(entryDetail(ledger, dinner), '預定 · 飲食 · 銀行');
    expect(
      entryDetails(ledger.accounts, dinner, '飲食', today: ledger.today),
      contains(('日期', '11 月 28 日 · 週六 · 預定')),
    );
    final lunch = ledger.entries.byId('lunch')!;
    expect(entryDetail(ledger, lunch), '飲食 · 銀行');
  });

  test('at the rollover to its day it counts, with nothing written', () {
    final dinner = ledger.entries.byId('dinner');
    today = DateTime.utc(2026, 11, 28);
    ledger.checkDay();
    // Nothing was written: the entry is the one kept before.
    expect(identical(ledger.entries.byId('dinner'), dinner), isTrue);
    // 10,000 - 1,000 - 300 - 5,000 = 3,700.
    expect(ledger.balanceService.balance('bank'), 3700);
    // 3,700 in the bank and nothing owed on the card.
    expect(ledger.balanceService.netWorthAt(ledger.today), 3700);
    // 6,000 + 300 = 6,300.
    expect(ledger.reportService.expense(2026, 11), 6300);
    final food = ledger.budgets.all.firstWhere((b) => b.category == '飲食');
    expect(ledger.budgetService.spentAgainst(food, 2026, 11), 6300);
    expect(ledger.statementService.statementDue(ledger.account('card')), 0);
    expect(
      ledger.statementService.billStatus(ledger.account('card')),
      const BillPaid(),
    );
    expect(november().planned, isEmpty);
    expect(entryDetail(ledger, ledger.entries.byId('dinner')!), '飲食 · 銀行');
  });

  test('up to a year ahead, and no trade before its day', () {
    // 2026-11-24 + 365 days = 2027-11-24.
    ledger.entryCommands.add(
      entryOf('rent', DateTime.utc(2027, 11, 24), EntryType.expense, 1, 'bank'),
    );
    expect(
      () => ledger.entryCommands.add(
        entryOf(
          'far',
          DateTime.utc(2027, 11, 25),
          EntryType.expense,
          1,
          'bank',
        ),
      ),
      throwsA(
        isA<RecordRefused>().having(
          (r) => r.first,
          'first',
          isA<DateTooFarAhead>().having((i) => i.days, 'days', 365),
        ),
      ),
    );
    expect(
      () => ledger.entryCommands.add(
        entryOf(
          'buy',
          DateTime.utc(2026, 11, 25),
          EntryType.buy,
          1000,
          'bank',
          holding: '2330',
          shares: 1,
        ),
      ),
      throwsA(
        isA<RecordRefused>().having(
          (r) => r.first,
          'first',
          isA<InvestmentPlanned>(),
        ),
      ),
    );
  });

  group('tags and a card leave 預定 out too (D71)', () {
    late Ledger book;
    setUp(() {
      book = ledgerOf(
        today: today,
        clock: () => today,
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 10000),
          Account(
            'card',
            '信用卡',
            AccountKind.card,
            0,
            closingDay: 10,
            dueDay: 30,
          ),
        ],
        categories: [Category('飲食', 'food', 0xFF5C9A83)],
        entries: [
          entryOf(
            'a',
            DateTime.utc(2026, 11, 20),
            EntryType.expense,
            1000,
            'bank',
            category: '飲食',
            tags: const ['旅行'],
          ),
          entryOf(
            'c',
            DateTime.utc(2026, 11, 15),
            EntryType.expense,
            400,
            'card',
            category: '飲食',
          ),
        ],
      );
      book.entryCommands.add(
        entryOf(
          'p',
          DateTime.utc(2026, 11, 28),
          EntryType.expense,
          300,
          'bank',
          category: '飲食',
          tags: const ['旅行'],
        ),
      );
      book.entryCommands.add(
        entryOf(
          'pc',
          DateTime.utc(2026, 11, 29),
          EntryType.expense,
          700,
          'card',
          category: '飲食',
        ),
      );
    });

    test('tag stats count 1,000 in one entry, not 1,300 in two', () {
      expect(book.reportService.tagStats, [('旅行', 1, 1000)]);
      expect(
        book.reportService.tagsBetween(
          DateTime.utc(2026, 11),
          DateTime.utc(2026, 11, 30),
        ),
        [('旅行', 1000)],
      );
      // At midnight of 11/28 the 300 joins: 1,000 + 300 = 1,300.
      today = DateTime.utc(2026, 11, 28);
      book.checkDay();
      expect(book.reportService.tagStats, [('旅行', 2, 1300)]);
    });

    test('a tag as a project sums what counts and lists every entry', () {
      final trip = tagSummaryOf(book.entries, '旅行', today)!;
      expect(trip.spent, 1000);
      expect(
        (trip.from, trip.to),
        (DateTime.utc(2026, 11, 20), DateTime.utc(2026, 11, 20)),
      );
      expect([for (final e in trip.entries) e.id], ['p', 'a']);
      expect(latestTag(book.entries, today), '旅行');
    });

    test("the card's unbilled purchases leave the 預定 one out", () {
      final card = book.accounts.byId('card')!;
      expect(book.statementService.unbilled(card).map((e) => e.id), ['c']);
      today = DateTime.utc(2026, 11, 29);
      book.checkDay();
      expect(book.statementService.unbilled(card).map((e) => e.id), [
        'pc',
        'c',
      ]);
    });
  });

  test("an old book's trade dated later joins the holdings on its day", () {
    // Written before D70 refused it: 10 shares bought 11/1, 5 more dated
    // 11/30.
    Entry buy(String id, int date, int shares) => entryOf(
      id,
      DateTime.utc(2026, 11, date),
      EntryType.buy,
      shares * 100,
      'bank',
      holding: '2330',
      shares: shares,
    );
    final old = ledgerOf(
      today: today,
      clock: () => today,
      accounts: const [Account('bank', '銀行', AccountKind.bank, 10000)],
      entries: [buy('b1', 1, 10), buy('b2', 30, 5)],
    );
    expect(old.holdings.byCode('2330')?.shares, 10);
    today = DateTime.utc(2026, 11, 30);
    old.checkDay();
    // 10 + 5 = 15.
    expect(old.holdings.byCode('2330')?.shares, 15);
  });
}
