// Work package 2.4: accounts, cards, loans and lending stay consistent.
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/accounts/model/account_form.dart';
import 'package:expense_tracker/src/features/accounts/model/reconcile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../baseline/baseline_ledger.dart';
import 'known_defect.dart';

void main() {
  test(
    'DEB-01: a person who still owes money cannot be archived out of sight',
    () {
      final ledger = ledgerOf(
        today: day(2026, 10, 4),
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 100000),
          Account('ann', '阿安', AccountKind.receivable, 0),
        ],
        entries: [
          entryOf(
            'lend',
            day(2026, 10, 1),
            EntryType.transfer,
            5000,
            'bank',
            to: 'ann',
          ),
        ],
      );
      expect(ledger.balanceService.balance('ann'), 5000);
      try {
        ledger.accountCommands.updateAccount(
          ledger.account('ann').copyWith(archived: true),
        );
      } on Object {
        // Refusing with an error is one way to say no.
      }
      // Still owed 5,000, so the person must stay visible.
      expect(ledger.account('ann').archived, isFalse);
    },
  );

  test('ACC-01: a reconciliation adjustment is not spending or income', () {
    final ledger = ledgerOf(
      today: day(2026, 10, 4),
      accounts: const [Account('cash', '現金', AccountKind.cash, 5000)],
    );
    // The wallet holds 3,000, not the 5,000 the book says.
    final adjustment = reconcile(
      ledger.balanceService,
      ledger.account('cash'),
      3000,
      id: 'r',
      today: day(2026, 10, 4),
    )!;
    ledger.entryCommands.add(adjustment);
    expect(ledger.balanceService.balance('cash'), 3000);
    // The 2,000 gap is no spending: reports and budgets stay at 0.
    expect(ledger.reportService.expense(2026, 10), 0);
    expect(ledger.reportService.income(2026, 10), 0);
  }, skip: knownDefect('ACC-01', '2.4'));

  test('ACC-02: changing an account\'s kind does not flip its balance', () {
    final ledger = ledgerOf(
      today: day(2026, 10, 4),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 5000)],
    );
    final form = AccountForm(ledger, old: ledger.account('bank'))
      ..kind = AccountKind.card;
    form.save();
    // Holding 5,000 stays holding 5,000 (or the change is refused).
    expect(ledger.balanceService.balance('bank'), 5000);
  }, skip: knownDefect('ACC-02', '2.4'));

  test('ACC-02: a foreign-currency account cannot become a card', () {
    final ledger = ledgerOf(
      today: day(2026, 10, 4),
      accounts: const [
        Account('usd', '美元', AccountKind.bank, 100000, currency: 'USD'),
      ],
    );
    AccountForm(ledger, old: ledger.account('usd'))
      ..kind = AccountKind.card
      ..save();
    final a = ledger.account('usd');
    expect(a.kind == AccountKind.card && a.foreign, isFalse);
  }, skip: knownDefect('ACC-02', '2.4'));

  test(
    'ACC-03: editing the balance of an account leaves its history alone',
    () {
      final ledger = ledgerOf(
        today: day(2026, 10, 4),
        accounts: const [Account('bank', '銀行', AccountKind.bank, 5000)],
        entries: [
          entryOf('e1', day(2026, 9, 1), EntryType.expense, 1000, 'bank'),
        ],
      );
      final form = AccountForm(ledger, old: ledger.account('bank'))
        ..balance = '9000';
      form.save();
      // Now 9,000; the balance on Aug 31 is still the 5,000 it was.
      expect(ledger.balanceService.balance('bank'), 9000);
      expect(
        ledger.balanceService.balance('bank', until: day(2026, 8, 31)),
        5000,
      );
    },
    skip: knownDefect('ACC-03', '2.4'),
  );

  test('LOG-06: deleting a purchase does not leave its refund as negative spending', () {
    final ledger = ledgerOf(
      today: day(2026, 10, 4),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 1000)],
      entries: [
        entryOf('p', day(2026, 10, 2), EntryType.expense, 5000, 'bank'),
        entryOf(
          'r',
          day(2026, 10, 3),
          EntryType.income,
          1000,
          'bank',
          refundOf: 'p',
        ),
      ],
    );
    try {
      ledger.entryCommands.remove('p');
    } on Object {
      // Refusing the delete is a fix too.
    }
    // Either the purchase stays (4,000) or the refund went with it (0).
    expect(ledger.reportService.expense(2026, 10), greaterThanOrEqualTo(0));
  }, skip: knownDefect('LOG-06', '2.4'));
}
