// Balances, net worth, foreign-currency transfers, refunds and money
// lent to people (代墊). A tiny ledger per test, every figure hand-made.
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'baseline_ledger.dart';

void main() {
  group('balances on a tiny ledger', () {
    // bank 1000, cash 50; on Oct 1 income 500 to the bank, on Oct 2 an
    // expense of 120 from the bank, on Oct 3 200 moved from bank to cash
    // with a 15 fee.
    Ledger book() => ledgerOf(
      today: day(2026, 10, 10),
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 1000),
        Account('cash', '現金', AccountKind.cash, 50),
      ],
      entries: [
        entryOf('i', day(2026, 10, 1), EntryType.income, 500, 'bank'),
        entryOf('e', day(2026, 10, 2), EntryType.expense, 120, 'bank'),
        entryOf(
          't',
          day(2026, 10, 3),
          EntryType.transfer,
          200,
          'bank',
          to: 'cash',
          fee: 15,
        ),
      ],
    );

    test('today: bank 1,165 and cash 250', () {
      final ledger = book();
      // Bank: 1000 + 500 - 120 - (200 + 15 fee) = 1165.
      expect(ledger.balanceService.balance('bank'), 1165);
      // Cash: 50 + 200 = 250 (the fee is the bank\'s).
      expect(ledger.balanceService.balance('cash'), 250);
    });
    test('the balance on an earlier day stops at that day', () {
      final ledger = book();
      int bank(int d) =>
          ledger.balanceService.balance('bank', until: day(2026, 10, d));
      // After Oct 1: 1000 + 500 = 1500.
      expect(bank(1), 1500);
      expect(
        ledger.balanceService.balance('bank', until: day(2026, 9, 30)),
        1000,
      );
      expect(bank(2), 1380); // 1500 - 120.
      expect(bank(3), 1165); // 1380 - 215.
    });
    test('the month shows income and spending, the move only its fee', () {
      final ledger = book();
      expect(ledger.reportService.income(2026, 10), 500);
      // 120 spent + 15 fee = 135; the 200 moved is not spending.
      expect(ledger.reportService.expense(2026, 10), 135);
    });
    test('the transfer arrives whole in the other account', () {
      final ledger = book();
      final t = ledger.entries.all.last;
      expect(ledger.balanceService.effect(t, 'bank'), -215);
      expect(ledger.balanceService.effect(t, 'cash'), 200);
    });
  });

  group('net worth is assets less debts', () {
    Ledger book() => ledgerOf(
      today: day(2026, 10, 10),
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 1000),
        Account('cash', '現金', AccountKind.cash, 50),
        Account('card', '信用卡', AccountKind.card, -300),
        Account('loan', '借款', AccountKind.loan, -2000),
        Account('hidden', '不計入', AccountKind.bank, 99999, inNetWorth: false),
      ],
    );

    test('assets leave debts out and the accounts marked not counted', () {
      // 1000 + 50 = 1050; the card and loan are debts, hidden is left out.
      expect(book().balanceService.assets, 1050);
    });
    test('debts are owed as positive amounts', () {
      final b = book().balanceService;
      expect(b.cardDebt, 300);
      expect(b.loanDebt, 2000);
    });
    test('net worth = 1050 - 300 - 2000 = -1250', () {
      expect(book().balanceService.netWorthAt(day(2026, 10, 10)), -1250);
    });
    test('paying the card from the bank leaves net worth unchanged', () {
      final ledger = book();
      ledger.entryCommands.add(
        entryOf(
          'pay',
          day(2026, 10, 10),
          EntryType.transfer,
          300,
          'bank',
          to: 'card',
        ),
      );
      // Bank 700, card 0: 700 + 50 + 0 - 2000 = -1250.
      expect(ledger.balanceService.balance('bank'), 700);
      expect(ledger.balanceService.balance('card'), 0);
      expect(ledger.balanceService.netWorthAt(day(2026, 10, 10)), -1250);
    });
    test('a card purchase raises the debt and lowers net worth', () {
      final ledger = book();
      ledger.entryCommands.add(
        entryOf('x', day(2026, 10, 10), EntryType.expense, 400, 'card'),
      );
      // Card -300 - 400 = -700; net worth -1250 - 400 = -1650.
      expect(ledger.balanceService.cardDebt, 700);
      expect(ledger.balanceService.netWorthAt(day(2026, 10, 10)), -1650);
    });
  });

  group('foreign-currency accounts', () {
    // US$ accounts count US cents. One US$ is NT$32.0.
    Ledger book({Map<String, double> rates = const {'USD': 32.0}}) => ledgerOf(
      today: day(2026, 10, 10),
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 100000),
        Account('usd', '美元', AccountKind.bank, 10000, currency: 'USD'),
      ],
      rates: rates,
    );

    test('US\$100.00 at 32.0 is worth NT\$3,200', () {
      // 10000 cents / 100 x 32 = 3200.
      final ledger = book();
      expect(ledger.balanceService.worthOf(ledger.account('usd')), 3200);
      expect(ledger.balanceService.assets, 103200);
    });
    test('without a rate the account is not counted and is listed', () {
      final ledger = book(rates: const {});
      expect(ledger.balanceService.worthOf(ledger.account('usd')), 0);
      expect(ledger.balanceService.assets, 100000);
      expect(ledger.balanceService.unrated.map((a) => a.id), ['usd']);
    });
    test('a transfer in carries the amount received, not a conversion', () {
      final ledger = book();
      // NT$3,200 out, US$100.00 (10000 cents) in; the 3200 is typed.
      ledger.entryCommands.add(
        entryOf(
          'in',
          day(2026, 10, 10),
          EntryType.transfer,
          3200,
          'bank',
          to: 'usd',
          received: 10000,
        ),
      );
      expect(ledger.balanceService.balance('bank'), 96800); // 100000-3200
      expect(ledger.balanceService.balance('usd'), 20000); // 10000+10000
    });
    test('a transfer out of the foreign account carries what was received', () {
      final ledger = book();
      // US$50.00 (5000 cents) out, NT$1,600 in.
      ledger.entryCommands.add(
        entryOf(
          'out',
          day(2026, 10, 10),
          EntryType.transfer,
          5000,
          'usd',
          to: 'bank',
          received: 1600,
        ),
      );
      expect(ledger.balanceService.balance('usd'), 5000); // 10000-5000
      expect(ledger.balanceService.balance('bank'), 101600); // 100000+1600
    });
    test('a foreign purchase lowers the account in cents, reports in NT\$', () {
      final ledger = book();
      // US$12.50 = 1250 cents, worth NT$400 that day.
      ledger.entryCommands.add(
        entryOf(
          'u',
          day(2026, 10, 10),
          EntryType.expense,
          1250,
          'usd',
          category: '購物',
          home: 400,
        ),
      );
      expect(ledger.balanceService.balance('usd'), 8750); // 10000-1250
      expect(ledger.reportService.expense(2026, 10), 400);
    });
    test(
      'a transfer between currencies with no amount received is refused',
      () {
        final ledger = book();
        expect(
          ledger.entryValidator.validate(
            entryOf(
              'x',
              day(2026, 10, 10),
              EntryType.transfer,
              3200,
              'bank',
              to: 'usd',
            ),
          ),
          isA<MissingReceivedAmount>(),
        );
      },
    );
    test('foreign spending with no NT\$ amount is refused', () {
      final ledger = book();
      expect(
        ledger.entryValidator.validate(
          entryOf('x', day(2026, 10, 10), EntryType.expense, 1250, 'usd'),
        ),
        isA<MissingHomeAmount>(),
      );
    });
  });

  group('refunds', () {
    Ledger book() => ledgerOf(
      today: day(2026, 10, 10),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 1000)],
      entries: [
        entryOf(
          'e',
          day(2026, 10, 2),
          EntryType.expense,
          400,
          'bank',
          category: '購物',
        ),
      ],
    );
    test('a refund of 150 returns 150 to the account', () {
      final ledger = book();
      ledger.entryCommands.add(
        entryOf(
          'r',
          day(2026, 10, 5),
          EntryType.income,
          150,
          'bank',
          category: '購物',
          refundOf: 'e',
        ),
      );
      // 1000 - 400 + 150 = 750.
      expect(ledger.balanceService.balance('bank'), 750);
    });
    test('no more than what is left can be refunded', () {
      final ledger = book();
      ledger.entryCommands.add(
        entryOf(
          'r',
          day(2026, 10, 5),
          EntryType.income,
          150,
          'bank',
          category: '購物',
          refundOf: 'e',
        ),
      );
      // 400 - 150 = 250 left; 251 is too much, 250 is fine.
      expect(
        ledger.entryValidator.validate(
          entryOf(
            'r2',
            day(2026, 10, 6),
            EntryType.income,
            251,
            'bank',
            category: '購物',
            refundOf: 'e',
          ),
        ),
        isA<RefundExceedsRemaining>(),
      );
      expect(
        ledger.entryValidator.validate(
          entryOf(
            'r3',
            day(2026, 10, 6),
            EntryType.income,
            250,
            'bank',
            category: '購物',
            refundOf: 'e',
          ),
        ),
        isNull,
      );
    });
  });

  group('money lent to people: repaying settles the oldest first', () {
    Ledger book({int owedAtStart = 0, List<Entry> more = const []}) => ledgerOf(
      today: day(2026, 10, 31),
      accounts: [
        const Account('bank', '銀行', AccountKind.bank, 100000),
        Account('ann', '阿安', AccountKind.receivable, owedAtStart),
      ],
      entries: [
        // Oct 1: lent 5000. Oct 10: lent 3000.
        entryOf(
          'l1',
          day(2026, 10, 1),
          EntryType.transfer,
          5000,
          'bank',
          to: 'ann',
        ),
        entryOf(
          'l2',
          day(2026, 10, 10),
          EntryType.transfer,
          3000,
          'bank',
          to: 'ann',
        ),
        ...more,
      ],
    );
    Entry back(String id, int d, int amount) => entryOf(
      id,
      day(2026, 10, d),
      EntryType.transfer,
      amount,
      'ann',
      to: 'bank',
    );
    List<(String, int)> owed(Ledger l) => [
      for (final (e, left) in l.reportService.owedBy('ann')) (e.id, left),
    ];

    test('nothing repaid: both sums are owed, newest first', () {
      final ledger = book();
      expect(owed(ledger), [('l2', 3000), ('l1', 5000)]);
      // 5000 + 3000 = 8000.
      expect(ledger.balanceService.balance('ann'), 8000);
    });
    test('4,000 back clears 4,000 of the oldest sum', () {
      final ledger = book(more: [back('p', 20, 4000)]);
      // l1: 5000 - 4000 = 1000 left; l2 untouched at 3000.
      expect(owed(ledger), [('l2', 3000), ('l1', 1000)]);
      // The balance agrees: 8000 - 4000 = 4000 = 3000 + 1000.
      expect(ledger.balanceService.balance('ann'), 4000);
    });
    test('5,000 back clears the oldest sum exactly', () {
      final ledger = book(more: [back('p', 20, 5000)]);
      expect(owed(ledger), [('l2', 3000)]);
      expect(ledger.balanceService.balance('ann'), 3000);
    });
    test('6,500 back clears the oldest and part of the next', () {
      final ledger = book(more: [back('p', 20, 6500)]);
      // 5000 to l1, 1500 to l2 -> 1500 left on l2.
      expect(owed(ledger), [('l2', 1500)]);
      expect(ledger.balanceService.balance('ann'), 1500);
    });
    test('two partial repayments add up the same way', () {
      final ledger = book(more: [back('p1', 15, 2000), back('p2', 20, 2500)]);
      // 4500 back: 4500 off l1 -> 500 left; l2 3000.
      expect(owed(ledger), [('l2', 3000), ('l1', 500)]);
      expect(ledger.balanceService.balance('ann'), 3500);
    });
    test('everything back leaves nothing owed', () {
      final ledger = book(more: [back('p', 20, 8000)]);
      expect(owed(ledger), isEmpty);
      expect(ledger.balanceService.balance('ann'), 0);
    });
    test('what was owed from the start is paid back first', () {
      // They already owed 2000 before the book began.
      final ledger = book(owedAtStart: 2000, more: [back('p', 20, 4000)]);
      // 2000 clears the opening debt, 2000 more comes off l1 -> 3000 left.
      expect(owed(ledger), [('l2', 3000), ('l1', 3000)]);
      // 2000 + 5000 + 3000 - 4000 = 6000 = 3000 + 3000.
      expect(ledger.balanceService.balance('ann'), 6000);
    });
    test('the bank side agrees: lent out and paid back', () {
      final ledger = book(more: [back('p', 20, 4000)]);
      // 100000 - 5000 - 3000 + 4000 = 96000.
      expect(ledger.balanceService.balance('bank'), 96000);
    });
  });
}
