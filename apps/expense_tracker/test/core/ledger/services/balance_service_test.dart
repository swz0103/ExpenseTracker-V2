import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/book.dart';

void main() {
  test('a balance is the opening sum and every entry up to the day', () {
    final book = Book(
      entries: [
        entry('a', amount: 300, date: DateTime.utc(2026, 9, 1)),
        entry('b', type: EntryType.income, amount: 500),
        entry('c', type: EntryType.transfer, amount: 200, to: 'cash'),
      ],
    );
    expect(book.balances.balance('bank'), 1000 - 300 + 500 - 200);
    expect(book.balances.balance('cash'), 50 + 200);
    expect(
      book.balances.balance('bank', until: DateTime.utc(2026, 9, 30)),
      700,
    );
  });

  test("an account's entries, newest first, both ends of a transfer", () {
    final book = Book(
      entries: [
        entry('a', amount: 300, date: DateTime.utc(2026, 9, 1)),
        entry('c', type: EntryType.transfer, amount: 200, to: 'cash'),
        entry('b', type: EntryType.income, amount: 500, account: 'cash'),
      ],
    );
    expect([for (final e in book.balances.entriesOf('bank')) e.id], ['c', 'a']);
    expect([for (final e in book.balances.entriesOf('cash')) e.id], ['b', 'c']);
    expect(book.balances.entriesOf('gone'), isEmpty);
  });

  test("an account's flow in a month, in and out apart", () {
    final book = Book(
      entries: [
        entry('old', amount: 999, date: DateTime.utc(2026, 9, 30)),
        entry('a', amount: 300),
        entry('b', type: EntryType.income, amount: 500),
        entry('c', type: EntryType.transfer, amount: 200, to: 'cash'),
      ],
    );
    // October: 500 in; 300 + 200 out. September's 999 is not counted.
    expect(book.balances.flowOf('bank', day), (inflow: 500, outflow: 500));
    // The cash account received the 200 transfer.
    expect(book.balances.flowOf('cash', day), (inflow: 200, outflow: 0));
    expect(book.balances.flowOf('bank', DateTime.utc(2026, 9, 1)), (
      inflow: 0,
      outflow: 999,
    ));
  });

  test('an account the book has none of has a balance of nothing', () {
    expect(Book().balances.balance('gone'), 0);
  });

  test('a balance is worked out again only after its topics change', () {
    final book = Book(entries: [entry('a', amount: 300)]);
    expect(book.balances.balance('bank'), 700);
    book.entries.add(entry('b', amount: 100));
    // Still the answer worked out before: nothing said the entries changed.
    expect(book.balances.balance('bank'), 700);
    book.cache.forget(const {Topic.budgets});
    expect(book.balances.balance('bank'), 700);
    book.cache.forget(const {Topic.entries});
    expect(book.balances.balance('bank'), 600);
  });

  test('a change to one account\'s entries leaves the others\' balances '
      'as they were, and moves its own', () {
    final book = Book(
      entries: [
        entry('a', amount: 300),
        entry('t', type: EntryType.transfer, amount: 200, to: 'cash'),
      ],
    );
    expect(book.balances.balance('bank'), 1000 - 300 - 200);
    expect(book.balances.balance('cash'), 50 + 200);
    book.entries.add(entry('b', amount: 100));
    book.cache.forget(const {Topic.entries});
    expect(book.balances.balance('bank'), 1000 - 300 - 200 - 100);
    expect(book.balances.balance('cash'), 250, reason: 'kept, and still so');
    // The transfer made smaller: both of its ends move.
    book.entries[1] = entry(
      't',
      type: EntryType.transfer,
      amount: 50,
      to: 'cash',
    );
    book.cache.forget(const {Topic.entries});
    expect(book.balances.balance('cash'), 50 + 50);
    expect(book.balances.balance('bank'), 1000 - 300 - 50 - 100);
  });

  test('a foreign account without a rate is left out of the worth', () {
    final book = Book(
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 1000),
        Account('usd', '美元', AccountKind.bank, 10000, currency: 'USD'),
      ],
    );
    expect(book.balances.unrated.map((a) => a.id), ['usd']);
    expect(book.balances.assets, 1000);
  });

  test('a foreign account counts at its rate once there is one', () {
    final book = Book(
      accounts: const [
        Account('usd', '美元', AccountKind.bank, 10000, currency: 'USD'),
      ],
      rates: {'USD': 32},
    );
    expect(book.balances.unrated, isEmpty);
    // 10000 cents is 100 dollars.
    expect(book.balances.assets, 3200);
  });

  test('what is owed on cards and loans is told apart from assets', () {
    final book = Book(
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 1000),
        Account('card', '卡', AccountKind.card, -300),
        Account('loan', '房貸', AccountKind.loan, -5000),
      ],
    );
    expect(book.balances.assets, 1000);
    expect(book.balances.cardDebt, 300);
    expect(book.balances.loanDebt, 5000);
    expect(book.balances.netWorthAt(day), 1000 - 300 - 5000);
  });

  test('each week of the last four shows how the account moved', () {
    final book = Book(
      entries: [
        entry('a', amount: 100, date: DateTime.utc(2026, 9, 30)),
        entry('b', amount: 50, date: DateTime.utc(2026, 10, 3)),
        entry('c', amount: 999, date: DateTime.utc(2026, 8, 1)),
      ],
    );
    final weeks = book.balances.weeklyChanges('bank');
    expect(weeks, hasLength(4));
    // Today is a Sunday, the first day of its week: nothing yet. The week
    // before began on Sunday the 27th and holds both entries.
    expect(weeks.last, (DateTime.utc(2026, 10, 4), 0));
    expect(weeks[2], (DateTime.utc(2026, 9, 27), -150));
    expect(weeks.first.$2, 0);
  });

  group('one net worth (D63)', () {
    test('a card paid past what it owed is held, not dropped', () {
      final book = Book(
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 1000),
          Account('card', '卡', AccountKind.card, 5000),
        ],
      );
      final worth = book.balances.netWorth(day);
      // Held: bank 1000 + the card's credit 5000 = 6000; nothing owed.
      expect(worth.saved, 6000);
      expect(worth.owed, 0);
      expect(worth.net, 6000);
      expect(book.balances.netWorthAt(day), 6000);
      expect(book.balances.assets, 6000);
      expect(book.balances.cardDebt, 0);
    });

    test('one card in credit and one in debt each stand on their side', () {
      final book = Book(
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 1000),
          Account('c1', '卡甲', AccountKind.card, 5000),
          Account('c2', '卡乙', AccountKind.card, -3000),
        ],
      );
      final worth = book.balances.netWorth(day);
      // Held 1000 + 5000 = 6000, owed 3000: 3000.
      expect((worth.held, worth.owed, worth.net), (6000, 3000, 3000));
      expect(book.balances.cardDebt, 3000);
    });

    test('nothing happened this month: the change since last month is 0', () {
      final book = Book(
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 1000),
          Account('card', '卡', AccountKind.card, 5000),
        ],
      );
      final moved =
          book.balances.netWorth(day).net -
          book.balances.netWorthAt(DateTime.utc(2026, 9, 30));
      expect(moved, 0);
    });

    test('the parts: in accounts, in shares, lent, owed', () {
      final book = Book(
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 1000),
          Account('ming', '小明', AccountKind.receivable, 300),
          Account('amy', '小美', AccountKind.receivable, -200),
          Account('loan', '房貸', AccountKind.loan, -5000),
        ],
      );
      final worth = book.balances.netWorth(day);
      // Saved 1000, lent 300; owed: what is owed to 小美 200 + the loan
      // 5000 = 5200; net 1300 - 5200 = -3900.
      expect(worth.saved, 1000);
      expect(worth.invested, 0);
      expect(worth.lent, 300);
      expect(worth.owed, 5200);
      expect(worth.net, -3900);
    });
  });

  group('foreign balances by side (D59)', () {
    test('a US\$ card debt is valued at the selling rate, a deposit at '
        'the buying rate', () {
      final book = Book(
        accounts: const [
          Account('usd', '美元', AccountKind.bank, 10000, currency: 'USD'),
          Account(
            'uc',
            '美元卡',
            AccountKind.card,
            -10000,
            currency: 'USD',
            closingDay: 5,
            dueDay: 20,
          ),
        ],
        rates: {'USD': 32},
        sellRates: {'USD': 32.5},
      );
      // US$100 held x 32 = 3200; US$100 owed x 32.5 = 3250.
      expect(book.balances.worthOf(book.accounts.resolve('usd')), 3200);
      expect(book.balances.worthOf(book.accounts.resolve('uc')), -3250);
      expect(book.balances.cardDebt, 3250);
      // 3200 - 3250 = -50: the spread is owed too.
      expect(book.balances.netWorthAt(day), -50);
    });
  });

  group('a refund of a purchase in instalments', () {
    const card = Account(
      'card',
      '信用卡',
      AccountKind.card,
      0,
      closingDay: 5,
      dueDay: 20,
    );
    Book make({int? refund = 1200}) => Book(
      accounts: const [Account('bank', '銀行', AccountKind.bank, 0), card],
      entries: [
        entry(
          'p',
          date: DateTime.utc(2026, 8, 10),
          amount: 1200,
          account: 'card',
          installments: 12,
        ),
        if (refund != null)
          entry(
            'r',
            type: EntryType.income,
            date: DateTime.utc(2026, 9, 20),
            amount: refund,
            account: 'card',
            refundOf: 'p',
          ),
      ],
    );

    test('refunded in full, the card owes nothing at once', () {
      final book = make();
      // 100 billed on 9/5; on 9/20 the 1100 not billed is billed at once
      // and the 1200 given back: -100 - 1100 + 1200 = 0.
      expect(
        book.balances.balance('card', until: DateTime.utc(2026, 9, 19)),
        -100,
      );
      expect(book.balances.balance('card'), 0);
      expect(
        book.balances.balance('card', until: DateTime.utc(2027, 12, 31)),
        0,
      );
      expect(book.balances.netWorthAt(day), 0);
      expect(book.balances.stillToBill(book.entries.byId('p')!), 0);
      expect(book.statements.instalmentsOn(card), isEmpty);
      // What the refund did to the card: +100 net.
      expect(book.balances.effect(book.entries.byId('r')!, 'card'), 100);
    });

    test('half refunded, the instalments left shrink by half', () {
      final book = make(refund: 600);
      // 1100 not billed by 9/20: 600 billed at once, the 500 left shared
      // over the 11 instalments of 100 -> 46 or 45 each.
      expect(book.balances.balance('card'), -100);
      expect(book.balances.stillToBill(book.entries.byId('p')!), 500);
      expect(
        book.balances.balance('card', until: DateTime.utc(2027, 12, 31)),
        -600,
      );
    });

    test('the statement and what was spent since agree with the balance', () {
      final book = make();
      final c = book.accounts.resolve('card');
      // Closed 9/5 owing 100; since then the refund, +100 net.
      expect(book.statements.statementDue(c), 100);
      final since = book.statements
          .unbilled(c)
          .fold(0, (sum, e) => sum - book.balances.effect(e, 'card'));
      expect(since, -100);
      expect(-book.balances.balance('card'), 100 + since);
    });
  });

  group('flows follow the days the balance moves', () {
    const card = Account(
      'card',
      '信用卡',
      AccountKind.card,
      0,
      closingDay: 5,
      dueDay: 20,
    );
    Book make() => Book(
      accounts: const [Account('bank', '銀行', AccountKind.bank, 0), card],
      entries: [
        entry(
          'p',
          date: DateTime.utc(2026, 8, 10),
          amount: 1200,
          account: 'card',
          installments: 12,
        ),
      ],
    );

    test('a month\'s flow is what its statements billed', () {
      final b = make().balances;
      // Bought 8/10, the first instalment billed 9/5.
      expect(b.flowOf('card', DateTime.utc(2026, 8, 1)), (
        inflow: 0,
        outflow: 0,
      ));
      expect(b.flowOf('card', DateTime.utc(2026, 9, 1)), (
        inflow: 0,
        outflow: 100,
      ));
    });

    test('the weeks add up to how the balance moved over them', () {
      final b = make().balances;
      final weeks = b.weeklyChanges('card', weeks: 8);
      final sum = weeks.fold(0, (s, w) => s + w.$2);
      final before = weeks.first.$1.subtract(const Duration(days: 1));
      // Of the statements, only 9/5 closes in the 8 weeks to 10/4: -100.
      expect(sum, b.balance('card') - b.balance('card', until: before));
      expect(sum, -100);
    });
  });

  group('edges review 11 found untested', () {
    test('a transfer takes its fee from where it left and brings what '
        'arrived where it went', () {
      final book = Book(
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 10000),
          Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
        ],
        entries: [
          Entry(
            id: 't',
            date: day,
            type: EntryType.transfer,
            amount: 3200,
            fee: 15,
            account: 'bank',
            to: 'usd',
            received: 10000,
          ),
        ],
      );
      // 10,000 - 3,200 - 15; US\$100.00 arrived.
      expect(book.balances.balance('bank'), 6785);
      expect(book.balances.balance('usd'), 10000);
    });

    test('an account left out of the net worth counts in none of it', () {
      final book = Book(
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 1000),
          Account('side', '私房', AccountKind.bank, 500, inNetWorth: false),
          Account('card', '卡', AccountKind.card, -300),
          Account('old', '舊卡', AccountKind.card, -700, inNetWorth: false),
        ],
      );
      final worth = book.balances.netWorth(day);
      expect((worth.saved, worth.owed), (1000, 300));
      expect(book.balances.cardDebt, 300);
    });

    test('the worth of a day gone by counts what was then', () {
      final book = Book(
        entries: [entry('a', amount: 300, date: DateTime.utc(2026, 9, 15))],
      );
      // bank 1000 and cash 50 on 9/1; 300 less once spent.
      expect(book.balances.netWorth(DateTime.utc(2026, 9, 1)).saved, 1050);
      expect(book.balances.netWorth(day).saved, 750);
    });

    test('a week runs from its Sunday to its Saturday, both counted', () {
      final book = Book(
        entries: [
          entry('a', amount: 10, date: DateTime.utc(2026, 9, 20)),
          entry('b', amount: 20, date: DateTime.utc(2026, 9, 26)),
          entry('c', amount: 40, date: DateTime.utc(2026, 9, 27)),
        ],
      );
      expect(book.balances.weeklyChanges('bank'), [
        (DateTime.utc(2026, 9, 13), 0),
        // Sunday 9/20 to Saturday 9/26: 10 + 20.
        (DateTime.utc(2026, 9, 20), -30),
        // Sunday 9/27 to Saturday 10/3: 40.
        (DateTime.utc(2026, 9, 27), -40),
        (DateTime.utc(2026, 10, 4), 0),
      ]);
    });

    test('a new day is asked again: the flow and the weeks take in a 預定 '
        'entry once its day comes', () {
      final book = Book(
        entries: [entry('p', amount: 500, date: DateTime.utc(2026, 10, 6))],
      );
      expect(book.balances.flowOf('bank', day).outflow, 0);
      expect(book.balances.weeklyChanges('bank').last.$2, 0);
      book.today = DateTime.utc(2026, 10, 6);
      expect(book.balances.flowOf('bank', day).outflow, 500);
      expect(book.balances.weeklyChanges('bank').last.$2, -500);
    });

    test('a card given new billing days bills its instalments again by '
        'them', () {
      Account card(int closingDay) => Account(
        'card',
        '卡',
        AccountKind.card,
        0,
        closingDay: closingDay,
        dueDay: 20,
      );
      final book = Book(
        accounts: [card(25)],
        entries: [
          entry(
            'plan',
            account: 'card',
            amount: 3000,
            installments: 3,
            date: DateTime.utc(2026, 9, 1),
          ),
        ],
      );
      // Closing on the 25th: one share billed by 10/4 (on 9/25).
      expect(book.balances.balance('card'), -1000);
      book.accounts.replaceWith([card(2)]);
      book.cache.forget(const {Topic.accounts});
      // Closing on the 2nd: billed on 9/2 and 10/2.
      expect(book.balances.balance('card'), -2000);
    });
  });

  test('the shares of a day gone by are those then held (mutation review '
      '11)', () {
    final ledger = Ledger(
      today: day,
      accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
      categories: [],
      entries: [
        Entry(
          id: 'b',
          date: DateTime.utc(2026, 10, 2),
          type: EntryType.buy,
          amount: 1000,
          account: 'bank',
          category: investmentCategory,
          holding: '2330',
          shares: 10,
        ),
      ],
      holdings: const [
        Holding('2330', '台積電', shares: 0, price: 100, cost: 0, change: 0),
      ],
      budgets: const [],
      recurring: const [],
    );
    // None held on 10/1; 10 x 100 today.
    expect(
      ledger.balanceService.netWorth(DateTime.utc(2026, 10, 1)).invested,
      0,
    );
    expect(ledger.balanceService.netWorth(day).invested, 1000);
  });
}
