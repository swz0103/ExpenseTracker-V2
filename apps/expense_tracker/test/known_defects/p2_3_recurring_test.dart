// Work package 2.3: recurring items book once per due day, never blindly.
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/recurring/model/recurring_form.dart';
import 'package:flutter_test/flutter_test.dart';

import '../baseline/baseline_ledger.dart';
import 'known_defect.dart';

void main() {
  test(
    'LOG-01: a foreign recurring item with no rate is not booked as NT\$',
    () {
      // US$5.00 monthly (500 cents), due on the 5th; no rate is known.
      const item = Recurring(
        id: 'sub',
        name: '訂閱',
        amount: 500,
        day: 5,
        account: 'usd',
        category: '訂閱',
        auto: true,
      );
      final ledger = ledgerOf(
        today: day(2026, 10, 12),
        accounts: const [
          Account('usd', '美元', AccountKind.bank, 10000, currency: 'USD'),
        ],
        categories: [Category('訂閱', 'sub', 0xFF5C9A83)],
        recurring: [item.copyWith()],
      );
      final booked = ledger.recurringCommands.bookDue();
      // Booking US$5.00 as NT$500 would be wrong; it waits for a rate.
      expect(booked, 0);
      expect(ledger.entries.all, isEmpty);
    },
    skip: knownDefect('LOG-01', '2.3'),
  );

  test('REC-01: resuming a paused item does not book the paused months', () {
    var now = day(2026, 3, 20);
    const item = Recurring(
      id: 'nf',
      name: 'Netflix',
      amount: 390,
      day: 15,
      account: 'bank',
      category: '訂閱',
      auto: true,
    );
    final ledger = ledgerOf(
      today: now,
      clock: () => now,
      accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
      categories: [Category('訂閱', 'sub', 0xFF5C9A83)],
      entries: [
        for (final m in [1, 2, 3])
          entryOf(
            'b$m',
            day(2026, m, 15),
            EntryType.expense,
            390,
            'bank',
            category: '訂閱',
          ).copyForRecurring('nf'),
      ],
      recurring: [item],
    );
    ledger.recurringCommands.saveRecurring(item.copyWith(active: false));
    now = day(2026, 11, 21);
    ledger.checkDay();
    ledger.recurringCommands.saveRecurring(item.copyWith(active: true));
    ledger.recurringCommands.bookDue();
    // Nothing is booked for the months it was paused (April to November).
    final late = [
      for (final e in ledger.entries.all)
        if (e.recurring == 'nf' && e.date.isAfter(day(2026, 3, 31))) e.date,
    ];
    expect(late, isEmpty);
    expect(ledger.balanceService.balance('bank'), 100000 - 3 * 390);
  }, skip: knownDefect('REC-01', '2.3'));

  test(
    'F14: auto-booking does not repeat a period already entered by hand',
    () {
      const item = Recurring(
        id: 'v6',
        name: 'V6Test',
        amount: 333,
        day: 10,
        account: 'bank',
        category: '訂閱',
        auto: true,
        start: null,
      );
      final ledger = ledgerOf(
        today: day(2026, 11, 21),
        accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
        categories: [Category('訂閱', 'sub', 0xFF5C9A83)],
        entries: [
          // Entered by hand on Nov 10, not linked to the item.
          entryOf(
            'hand',
            day(2026, 11, 10),
            EntryType.expense,
            333,
            'bank',
            category: '訂閱',
          ),
        ],
        recurring: [
          Recurring(
            id: item.id,
            name: item.name,
            amount: item.amount,
            day: item.day,
            account: item.account,
            category: item.category,
            auto: true,
            start: day(2026, 11, 10),
          ),
        ],
      );
      ledger.recurringCommands.bookDue();
      final onTenth = [
        for (final e in ledger.entries.all)
          if (e.date == day(2026, 11, 10) && e.amount == 333) e,
      ];
      expect(onTenth, hasLength(1));
    },
    skip: knownDefect('F14', '2.3'),
  );

  test('F82: changing the start date keeps the day of the month chosen', () {
    final ledger = ledgerOf(
      today: day(2026, 10, 4),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 5000)],
      categories: [Category('居家', 'home', 0xFF5B8DB0)],
    );
    final form = RecurringForm(ledger)
      ..amount = 500
      ..setDayOfMonth(10);
    // The start picker then moves the start to the 1st of the month.
    form.start = day(2026, 11, 1);
    expect(form.save(), isTrue);
    // It still repeats on the 10th.
    expect(ledger.recurring.all.single.day, 10);
  }, skip: knownDefect('F82', '2.3'));

  test(
    'LOG-09: moving a booked entry to another date does not book it again',
    () {
      const item = Recurring(
        id: 'rent',
        name: '房租',
        amount: 10000,
        day: 1,
        account: 'bank',
        category: '居住',
      );
      final ledger = ledgerOf(
        today: day(2026, 10, 4),
        accounts: const [Account('bank', '銀行', AccountKind.bank, 1000)],
        entries: [
          entryOf(
            'a',
            day(2026, 9, 1),
            EntryType.expense,
            10000,
            'bank',
          ).copyForRecurring('rent'),
          entryOf(
            'b',
            day(2026, 10, 1),
            EntryType.expense,
            10000,
            'bank',
          ).copyForRecurring('rent'),
        ],
        recurring: [item],
      );
      ledger.entryCommands.replace(
        entryOf(
          'b',
          day(2026, 9, 30),
          EntryType.expense,
          10000,
          'bank',
        ).copyForRecurring('rent'),
      );
      // October's rent is still booked, only dated Sep 30: nothing is due.
      expect(ledger.recurringService.pendingDate(item), isNull);
    },
    skip: knownDefect('LOG-09', '2.3'),
  );
}

extension on Entry {
  /// This entry as the booking of recurring item [id].
  Entry copyForRecurring(String id) => Entry(
    id: this.id,
    date: date,
    type: type,
    amount: amount,
    account: account,
    category: category,
    recurring: id,
  );
}
