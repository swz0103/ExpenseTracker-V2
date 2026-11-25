import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// CORR-2: what the recurring commands write when days fall due, when a
/// day is brought back and when an item changes.
void main() {
  final today = DateTime.utc(2026, 11, 13);

  Recurring rent({
    bool auto = true,
    String account = 'bank',
    Set<DateTime> skipped = const {},
  }) => Recurring(
    id: 'rent',
    name: '房租',
    amount: 15000,
    day: 1,
    account: account,
    category: '居家',
    auto: auto,
    start: DateTime.utc(2026, 1, 1),
    skipped: skipped,
  );

  Entry booked(int month) => Entry(
    id: 'r$month',
    date: DateTime.utc(2026, month, 1),
    type: EntryType.expense,
    amount: 15000,
    account: 'bank',
    category: '居家',
    recurring: 'rent',
  );

  Ledger book({
    List<Recurring>? recurring,
    List<Entry> entries = const [],
    Map<String, double> rates = const {},
  }) => Ledger(
    today: today,
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 500000),
      Account('old', '舊帳戶', AccountKind.bank, 0, archived: true),
      Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
    ],
    categories: [Category('居家', 'home', 0xFF5B8DB0)],
    entries: entries,
    holdings: const [],
    budgets: const [],
    recurring: recurring ?? [rent()],
    rates: rates,
  );

  List<DateTime> days(Ledger ledger) => [
    for (final e in ledger.entries.all)
      if (e.recurring == 'rent') e.date,
  ]..sort();

  group('bookDue (D61)', () {
    test('one day waiting is booked by itself', () {
      final ledger = book(entries: [booked(10)]);
      final due = ledger.recurringCommands.bookDue();
      expect(due.booked, 1);
      expect(due.held, isEmpty);
      expect(days(ledger).last, DateTime.utc(2026, 11, 1));
    });

    test('more than one day waiting is held, listed with its days', () {
      final ledger = book(entries: [booked(8)]);
      final due = ledger.recurringCommands.bookDue();
      expect(due.booked, 0);
      final held = due.held.single;
      expect(held.days, [
        DateTime.utc(2026, 9, 1),
        DateTime.utc(2026, 10, 1),
        DateTime.utc(2026, 11, 1),
      ]);
      expect(
        (held.confirmable, held.closed, held.refusal),
        (true, false, null),
      );
      expect(ledger.entries.length, 1, reason: 'nothing booked yet');
    });

    test('an item into a closed account is held, not booked', () {
      final ledger = book(recurring: [rent(account: 'old')]);
      final held = ledger.recurringCommands.bookDue().held.single;
      expect((held.closed, held.confirmable), (true, false));
      expect(ledger.entries.all, isEmpty);
    });

    test('R5: a foreign day gone by waits with why', () {
      final ledger = book(
        recurring: [rent(account: 'usd')],
        rates: const {'USD': 32.0},
      );
      final held = ledger.recurringCommands.bookDue().held.single;
      expect(held.refusal, isA<MissingHomeAmount>());
      expect(held.confirmable, isFalse);
      expect(ledger.entries.all, isEmpty);
    });

    test('AutoBooking.none books and holds nothing', () {
      expect(AutoBooking.none.booked, 0);
      expect(AutoBooking.none.held, isEmpty);
    });
  });

  group('bookDays', () {
    test('books each day confirmed on its own day, all at once', () {
      final ledger = book(entries: [booked(8)]);
      final booked3 = ledger.recurringCommands.bookDays(
        ledger.recurring.all.single,
        [DateTime.utc(2026, 9, 1), DateTime.utc(2026, 11, 1)],
      );
      expect(booked3, 2);
      expect(days(ledger), [
        DateTime.utc(2026, 8, 1),
        DateTime.utc(2026, 9, 1),
        DateTime.utc(2026, 11, 1),
      ]);
    });

    test('at most bookedAtOnce days of one item in one go', () {
      final daily = Recurring(
        id: 'rent',
        name: '早餐',
        amount: 50,
        day: 1,
        account: 'bank',
        category: '居家',
        unit: RepeatUnit.day,
        start: DateTime.utc(2026, 1, 1),
      );
      final ledger = book(recurring: [daily]);
      final all = [
        for (var d = 0; d < 100; d++)
          DateTime.utc(2026, 1, 1).add(Duration(days: d)),
      ];
      expect(RecurringCommands.bookedAtOnce, 62);
      expect(ledger.recurringCommands.bookDays(daily, all), 62);
    });

    test('a foreign day with no rate of its own is left', () {
      final ledger = book(
        recurring: [rent(account: 'usd')],
        rates: const {'USD': 32.0},
      );
      final item = ledger.recurring.all.single;
      expect(
        ledger.recurringCommands.bookDays(item, [DateTime.utc(2026, 11, 1)]),
        0,
      );
    });
  });

  test('D66: confirm books the day asked for', () {
    final ledger = book(recurring: [rent(auto: false)]);
    ledger.recurringCommands.confirm(
      ledger.recurring.all.single,
      day: DateTime.utc(2026, 11, 1),
    );
    expect(days(ledger), [DateTime.utc(2026, 11, 1)]);
  });

  test('D66: 恢復 a day before every booking brings it back as due, and '
      '入帳 books that day', () {
    final ledger = book(
      recurring: [
        rent(auto: false, skipped: {DateTime.utc(2026, 6, 1)}),
      ],
      entries: [booked(10)],
    );
    final item = ledger.recurring.all.single;
    ledger.recurringCommands.unskip(item, DateTime.utc(2026, 6, 1));
    final back = ledger.recurring.all.single;
    expect(back.skipped, isEmpty);
    expect(back.openFrom, DateTime.utc(2026, 6, 1));
    expect(ledger.recurringService.pendingDate(back), DateTime.utc(2026, 6, 1));
    expect(
      ledger.recurringService.booking(back).date,
      DateTime.utc(2026, 6, 1),
    );
  });

  test('R4/F82: a day let go that the changed item no longer falls on is '
      'forgotten', () {
    final ledger = book(
      recurring: [
        rent(
          auto: false,
          skipped: {DateTime.utc(2026, 9, 1), DateTime.utc(2026, 10, 1)},
        ),
      ],
    );
    final old = ledger.recurring.all.single;
    // Now on the 10th: neither day let go is one of its days.
    ledger.recurringCommands.saveRecurring(
      Recurring(
        id: old.id,
        name: old.name,
        amount: old.amount,
        day: 10,
        account: old.account,
        category: old.category,
        start: old.start,
        skipped: {...old.skipped, DateTime.utc(2026, 11, 10)},
      ),
    );
    expect(ledger.recurring.all.single.skipped, {DateTime.utc(2026, 11, 10)});
  });

  test('a recurring item deleted comes back where it stood (D82)', () {
    Recurring item(String id) => Recurring(
      id: id,
      name: id,
      amount: 100,
      day: 1,
      account: 'bank',
      category: '居家',
    );
    final l = Ledger(
      today: today,
      accounts: const [Account('bank', '銀行', AccountKind.bank, 0)],
      categories: const [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: [item('a'), item('b'), item('c')],
    );
    final undo = l.recurringCommands.removeRecurring('b')!;
    expect([for (final r in l.recurring.all) r.id], ['a', 'c']);
    undo();
    expect([for (final r in l.recurring.all) r.id], ['a', 'b', 'c']);
    // Run again, no second copy.
    undo();
    expect(l.recurring.all, hasLength(3));
    expect(l.recurringCommands.removeRecurring('none'), isNull);
  });
}
