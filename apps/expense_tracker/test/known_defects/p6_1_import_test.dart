// Work package 6.1: a CSV import does what its screen promises.
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_page.dart'
    show importBookOf;
import 'package:flutter_test/flutter_test.dart';

import '../baseline/baseline_ledger.dart';
import 'known_defect.dart';

Ledger book(List<Account> accounts, List<Entry> entries) => ledgerOf(
  today: day(2026, 10, 20),
  accounts: accounts,
  categories: [
    Category('飲食', 'food', 0xFF111111),
    Category('薪水', 'salary', 0xFF222222, income: true),
  ],
  entries: entries,
);

void main() {
  test(
    'IMP-01: a positive amount with no type column is not taken as income',
    () {
      final ledger = book(const [
        Account('bank', '銀行', AccountKind.bank, 0),
      ], const []);
      final found = importCsv(
        importBookOf(ledger),
        '日期,金額\n2026-10-01,120\n',
        fallback: 'bank',
      );
      // The direction is not known: it must not silently become income.
      expect(found.entries.where((e) => e.type == EntryType.income), isEmpty);
    },
    skip: knownDefect('IMP-01', '6.1'),
  );

  test('IMP-02: the app\'s own export imports back with accounts and groups intact', () {
    final accounts = const [
      Account('bank', '日常銀行', AccountKind.bank, 5000),
      Account('usd', '美元帳戶', AccountKind.bank, 100000, currency: 'USD'),
      Account('card', '玉山信用卡', AccountKind.card, 0, closingDay: 20, dueDay: 5),
      Account('recv', '代墊款', AccountKind.receivable, 0),
    ];
    final entries = [
      entryOf(
        'u1',
        day(2026, 10, 1),
        EntryType.expense,
        1250,
        'usd',
        category: '飲食',
        merchant: '星巴克',
        home: 400,
      ),
      entryOf(
        'g1',
        day(2026, 10, 3),
        EntryType.expense,
        900,
        'bank',
        category: '飲食',
        merchant: '燒肉',
      ).inGroup('dinner-1'),
      entryOf(
        'g2',
        day(2026, 10, 3),
        EntryType.transfer,
        600,
        'bank',
        to: 'recv',
      ).inGroup('dinner-1'),
      entryOf(
        'i1',
        day(2026, 10, 4),
        EntryType.income,
        50000,
        'bank',
        category: '薪水',
        merchant: '某公司',
      ),
    ];
    final source = book(accounts, entries);
    final csv = toCsv(source.accounts, source.entries.all);
    final target = book(const [
      Account('cash', '現金', AccountKind.cash, 0),
      Account('bank0', '銀行', AccountKind.bank, 0),
    ], const []);
    final found = importCsv(importBookOf(target), csv, fallback: 'bank0');
    addImport(target.entryCommands, found);

    Account named(String name) =>
        target.accounts.all.firstWhere((a) => a.name == name);
    Entry byDay(int d, EntryType type) => target.entries.all.firstWhere(
      (e) => e.date == day(2026, 10, d) && e.type == type,
    );
    // The US$ account is still US$, with its opening balance.
    expect(named('美元帳戶').currency, 'USD');
    expect(named('美元帳戶').opening, 100000);
    expect(named('日常銀行').opening, 5000);
    // The card keeps its billing days.
    expect((named('玉山信用卡').closingDay, named('玉山信用卡').dueDay), (20, 5));
    // US$12.50 stays 1250 cents worth NT$400.
    final dollars = byDay(1, EntryType.expense);
    expect((dollars.amount, dollars.home), (1250, 400));
    // The dinner and the money lent for it stay one group.
    expect(byDay(3, EntryType.expense).group, isNotNull);
    expect(
      byDay(3, EntryType.expense).group,
      byDay(3, EntryType.transfer).group,
    );
    // The employer is not lost.
    expect(byDay(4, EntryType.income).merchant, '某公司');
  }, skip: knownDefect('IMP-02', '6.1'));
}
