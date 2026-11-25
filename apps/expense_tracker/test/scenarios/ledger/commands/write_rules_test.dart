/// Every entry point that writes refuses a record the ledger's write
/// rules (package ledger_entries) refuse, whoever calls it, and changes
/// nothing (work package 1.4: LOG-02, LOG-03, LOG-07, LOG-11, F56, DAT-11).
library;

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../baseline/baseline_ledger.dart';

const _card = Account(
  'card',
  '信用卡',
  AccountKind.card,
  0,
  closingDay: 25,
  dueDay: 10,
);

Ledger _book({
  List<Entry> entries = const [],
  List<Recurring> recurring = const [],
}) => ledgerOf(
  today: day(2026, 10, 4),
  accounts: const [
    Account('bank', '銀行', AccountKind.bank, 1000),
    Account('cash', '現金', AccountKind.cash, 500),
    _card,
  ],
  entries: entries,
  recurring: recurring,
);

/// A spending of NT$100 from the bank on Oct 4.
Entry _spend(String id, {int amount = 100, String account = 'bank'}) =>
    entryOf(id, day(2026, 10, 4), EntryType.expense, amount, account);

/// A transfer with no receiving account: illegal (LOG-03).
Entry _nowhere(String id) =>
    entryOf(id, day(2026, 10, 4), EntryType.transfer, 100, 'bank');

Matcher _refused(Type issue) => isA<RecordRefused>().having(
  (r) => r.first.runtimeType,
  'first issue',
  issue,
);

void main() {
  group('D6: a day trade, kept by the model and the commands', () {
    // 1000 shares of 2330 bought and sold the same day.
    Entry trade(String id, EntryType type, {bool dayTrade = false}) => Entry(
      id: id,
      date: day(2026, 10, 4),
      type: type,
      amount: 100000,
      account: 'bank',
      category: investmentCategory,
      holding: '2330',
      shares: 1000,
      // 100,000 x 0.15% = 150 for the day-trade sale, 300 otherwise.
      tax: type == EntryType.sell ? (dayTrade ? 150 : 300) : 0,
      dayTrade: dayTrade,
    );

    test('a sale written as a day trade is kept as one', () {
      final ledger = _book();
      ledger.entryCommands.add(trade('b', EntryType.buy));
      ledger.entryCommands.add(trade('s', EntryType.sell, dayTrade: true));
      final kept = ledger.entries.byId('s')!;
      expect(kept.dayTrade, isTrue);
      // Settles at 100,000 less the 150 tax: 99,850.
      expect(kept.settlement, 99850);
    });

    test('a purchase cannot be a day trade', () {
      final ledger = _book();
      expect(
        () =>
            ledger.entryCommands.add(trade('b', EntryType.buy, dayTrade: true)),
        throwsA(_refused(DayTradeNotSale)),
      );
      expect(ledger.entries.all, isEmpty);
    });
  });

  group('entries', () {
    test('add refuses a transfer to nowhere', () {
      final ledger = _book();
      expect(
        () => ledger.entryCommands.add(_nowhere('t')),
        throwsA(_refused(MissingDestination)),
      );
      expect(ledger.entries.all, isEmpty);
    });

    test('save refuses split parts that do not add up, and keeps the rest', () {
      final ledger = _book(entries: [_spend('a')]);
      // 500 − (200 + 100) = 200 short.
      final split = entryOf(
        'a',
        day(2026, 10, 4),
        EntryType.expense,
        500,
        'bank',
        parts: const [('食', 200), ('衣', 100)],
      );
      expect(
        () => ledger.entryCommands.save([split], replacing: ['a']),
        throwsA(
          isA<RecordRefused>().having(
            (r) => r.first,
            'first',
            isA<SplitTotalMismatch>().having((s) => s.difference, 'diff', 200),
          ),
        ),
      );
      expect(ledger.entries.byId('a')!.amount, 100);
    });

    test('save refuses a split part of nothing (F56)', () {
      final ledger = _book();
      final split = entryOf(
        's',
        day(2026, 10, 4),
        EntryType.expense,
        100,
        'bank',
        parts: const [('食', 100), ('衣', 0)],
      );
      expect(
        () => ledger.entryCommands.save([split]),
        throwsA(_refused(SplitPartNotPositive)),
      );
      expect(ledger.entries.all, isEmpty);
    });

    test('save keeps a group and its receipt in one change', () {
      final ledger = _book();
      final own = _spend('own').inGroup('g');
      final lent = entryOf(
        'lent',
        day(2026, 10, 4),
        EntryType.transfer,
        50,
        'bank',
        to: 'cash',
      ).inGroup('g');
      ledger.entryCommands.save(
        [own, lent],
        receipt: 'r.etr',
        receiptOn: 'own',
      );
      expect(ledger.entries.all.map((e) => e.id), ['own', 'lent']);
      expect(ledger.receipts.of('own'), 'r.etr');
    });

    test('replace refuses instalments off a card', () {
      final ledger = _book(entries: [_spend('a')]);
      final spread = entryOf(
        'a',
        day(2026, 10, 4),
        EntryType.expense,
        100,
        'bank',
        installments: 3,
      );
      expect(
        () => ledger.entryCommands.replace(spread),
        throwsA(_refused(InstallmentsOffCard)),
      );
      expect(ledger.entries.byId('a')!.installments, 0);
    });

    test('addAll refuses an import holding an entry into no account', () {
      final ledger = _book();
      expect(
        () => ledger.entryCommands.addAll([
          _spend('a'),
          _spend('b', account: 'gone'),
        ]),
        throwsA(_refused(UnknownAccount)),
      );
      expect(ledger.entries.all, isEmpty);
    });

    test('addAll takes an entry into an account the import brings', () {
      final ledger = _book();
      ledger.entryCommands.addAll(
        [_spend('a', account: 'new')],
        accounts: const [Account('new', '新帳戶', AccountKind.cash, 0)],
      );
      expect(ledger.entries.all.single.account, 'new');
    });

    test('replaceAll refuses a date that is not a UTC midnight (DAT-11)', () {
      final ledger = _book(entries: [_spend('a')]);
      final local = Entry(
        id: 'a',
        date: DateTime(2026, 10, 4),
        type: EntryType.expense,
        amount: 100,
        account: 'bank',
      );
      expect(
        () => ledger.entryCommands.replaceAll([local]),
        throwsA(_refused(DateNotMidnight)),
      );
      expect(ledger.entries.byId('a')!.date, day(2026, 10, 4));
    });

    test('an amount above the most kept is refused', () {
      final ledger = _book();
      expect(
        () => ledger.entryCommands.add(_spend('a', amount: 1000000000)),
        throwsA(_refused(AmountTooLarge)),
      );
    });

    test('D12: an oversold sale is refused as the write rules refuse it', () {
      final ledger = _book();
      final sale = entryOf(
        's',
        day(2026, 10, 4),
        EntryType.sell,
        1000,
        'bank',
        holding: '2330',
        shares: 1,
      );
      expect(
        () => ledger.entryCommands.add(sale),
        throwsA(
          isA<RecordRefused>().having(
            (r) => r.first,
            'first',
            isA<SaleExceedsHolding>().having((i) => i.later, 'later', false),
          ),
        ),
      );
      expect(ledger.entries.all, isEmpty);
    });

    test('restore and the trash refuse, telling it through problem', () {
      // A transfer to nowhere kept by an older version, then deleted.
      final ledger = _book(entries: [_nowhere('t')]);
      final gone = ledger.entryCommands.remove('t')!;
      expect(ledger.entryCommands.restore(gone), isFalse);
      expect(ledger.problem.value, _refused(MissingDestination));
      ledger.problem.value = null;
      expect(ledger.entryCommands.restoreAll([gone]), isFalse);
      expect(ledger.problem.value, _refused(MissingDestination));
      ledger.problem.value = null;
      expect(
        ledger.entryCommands.restoreTrashed(ledger.trash.all.single),
        isFalse,
      );
      expect(ledger.problem.value, _refused(MissingDestination));
      expect(ledger.entries.all, isEmpty);
      expect(ledger.trash.all, hasLength(1));
    });

    test('a batch edit leaves out what the ledger would refuse', () {
      // An older foreign spending without its NT$ worth stays as it was.
      final ledger = ledgerOf(
        today: day(2026, 10, 4),
        accounts: const [
          Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
          Account('usd2', '美元二', AccountKind.bank, 0, currency: 'USD'),
        ],
        entries: [
          entryOf('old', day(2026, 10, 1), EntryType.expense, 100, 'usd'),
        ],
      );
      final old = ledger.entries.byId('old')!;
      expect(ledger.entryCommands.recategorize([old], '食'), 0);
      expect(ledger.entryCommands.moveToAccount([old], 'usd2'), 0);
      expect(ledger.entries.byId('old')!.account, 'usd');
    });
  });

  group('recurring items (LOG-07)', () {
    const rent = Recurring(
      id: 'rent',
      name: '房租',
      amount: 10000,
      day: 1,
      account: 'bank',
      category: '居住',
    );

    test('saveRecurring refuses every 0 and day 40', () {
      final ledger = _book();
      for (final (bad, issue) in [
        (
          const Recurring(
            id: 'r',
            name: 'r',
            amount: 1,
            day: 1,
            account: 'bank',
            category: '',
            every: 0,
          ),
          IntervalTooSmall,
        ),
        (
          const Recurring(
            id: 'r',
            name: 'r',
            amount: 1,
            day: 40,
            account: 'bank',
            category: '',
          ),
          DayOutOfRange,
        ),
      ]) {
        expect(
          () => ledger.recurringCommands.saveRecurring(bad),
          throwsA(_refused(issue)),
        );
      }
      expect(ledger.recurring.all, isEmpty);
    });

    test('confirm refuses a booking the ledger would not keep', () {
      final ledger = ledgerOf(
        today: day(2026, 10, 4),
        accounts: const [
          Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
        ],
        recurring: [rent.copyWith(account: 'usd')],
      );
      final item = ledger.recurring.all.single;
      expect(
        ledger.recurringCommands.refusalOf(item),
        isA<MissingHomeAmount>(),
      );
      expect(
        () => ledger.recurringCommands.confirm(item),
        throwsA(_refused(MissingHomeAmount)),
      );
      expect(ledger.entries.all, isEmpty);
    });

    test('bookDue leaves a booking into an account since deleted', () {
      final ledger = _book(
        recurring: [rent.copyWith(account: 'gone', auto: true)],
      );
      expect(ledger.recurringCommands.bookDue().booked, 0);
      expect(ledger.entries.all, isEmpty);
    });

    test('an item every 0 months falls due on no day, not forever', () {
      const stuck = Recurring(
        id: 's',
        name: 's',
        amount: 1,
        day: 1,
        account: 'bank',
        category: '',
        every: 0,
      );
      expect(stuck.datesIn(2026, 10), isEmpty);
    });
  });

  group('accounts (LOG-11, F68)', () {
    test('addAccount refuses a blank name', () {
      final ledger = _book();
      expect(
        () => ledger.accountCommands.addAccount(
          const Account('x', '  ', AccountKind.cash, 0),
        ),
        throwsA(_refused(BlankName)),
      );
      expect(ledger.accounts.byId('x'), isNull);
    });

    test('updateAccount refuses a closing day of 0 and a negative limit', () {
      final ledger = _book();
      expect(
        () =>
            ledger.accountCommands.updateAccount(_card.copyWith(closingDay: 0)),
        throwsA(_refused(ClosingDayOutOfRange)),
      );
      expect(
        () => ledger.accountCommands.updateAccount(_card.copyWith(limit: -1)),
        throwsA(_refused(NegativeCreditLimit)),
      );
      expect(ledger.account('card').closingDay, 25);
    });

    test('D116: addAccount and updateAccount refuse a loan rate below '
        'nothing', () {
      final ledger = _book();
      const loan = Account(
        'loan',
        '房貸',
        AccountKind.loan,
        -1000,
        loan: LoanTerms(rate: -100),
      );
      expect(
        () => ledger.accountCommands.addAccount(loan),
        throwsA(_refused(NegativeLoanRate)),
      );
      expect(ledger.accounts.byId('loan'), isNull);
      ledger.accountCommands.addAccount(
        const Account(
          'loan',
          '房貸',
          AccountKind.loan,
          -1000,
          loan: LoanTerms(rate: 200),
        ),
      );
      expect(
        () => ledger.accountCommands.updateAccount(loan),
        throwsA(_refused(NegativeLoanRate)),
      );
      expect(ledger.account('loan').loan?.rate, 200);
    });

    test('moveClose refuses a close moved more than a week', () {
      final ledger = _book();
      expect(
        () => ledger.accountCommands.moveClose(
          'card',
          day(2026, 10, 25),
          day(2026, 11, 3),
        ),
        throwsA(_refused(CloseMoveRefused)),
      );
      expect(ledger.account('card').closes, isEmpty);
      ledger.accountCommands.moveClose(
        'card',
        day(2026, 10, 25),
        day(2026, 10, 27),
      );
      expect(ledger.account('card').closes, {
        day(2026, 10, 25): day(2026, 10, 27),
      });
    });
  });

  group('budgets', () {
    test('setBudget refuses a negative limit and a warning of 0%', () {
      final ledger = _book();
      expect(
        () => ledger.budgetCommands.setBudget(allSpending, -1),
        throwsA(_refused(NegativeBudgetLimit)),
      );
      expect(
        () => ledger.budgetCommands.setBudget(allSpending, 100, warning: 0),
        throwsA(_refused(WarningOutOfRange)),
      );
      expect(ledger.budgets.all, isEmpty);
    });
  });

  group('the warning before a buy (F24)', () {
    test('a buy leaving cash below nothing is warned of, and kept', () {
      final ledger = _book();
      final buy = entryOf(
        'b',
        day(2026, 10, 4),
        EntryType.buy,
        600,
        'cash',
        holding: '2330',
        shares: 1,
        fee: 20,
      );
      // 500 − (600 + 20) = −120.
      final issues = ledger.entryValidator.issues(buy);
      expect(
        issues.single,
        isA<NegativeBalanceAfter>().having((n) => n.after, 'after', -120),
      );
      expect(ledger.entryValidator.validate(buy), isNull);
      ledger.entryCommands.add(buy);
      expect(ledger.balanceService.balance('cash'), -120);
    });
  });
}
