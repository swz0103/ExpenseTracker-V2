import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_json.dart';
import 'package:flutter_test/flutter_test.dart';

/// Recurring items booked by themselves: every period missed while the
/// app was not opened, however long; and a booking deleted stays deleted
/// (the code review of 2026-11-13, findings 1 and 2).
void main() {
  const rentId = 'rent';

  Recurring rent({Set<DateTime> skipped = const {}}) => Recurring(
    id: rentId,
    name: '房租',
    amount: 15000,
    day: 1,
    account: 'bank',
    category: '居家',
    auto: true,
    start: DateTime.utc(2026, 6, 1),
    skipped: skipped,
  );

  Entry booked(int month) => Entry(
    id: 'r$month',
    date: DateTime.utc(2026, month, 1),
    type: EntryType.expense,
    amount: 15000,
    account: 'bank',
    category: '居家',
    recurring: rentId,
  );

  Ledger book({required DateTime today, required List<Entry> entries}) =>
      Ledger(
        today: today,
        accounts: const [Account('bank', '銀行', AccountKind.bank, 500000)],
        categories: [Category('居家', 'home', 0xFF5B8DB0)],
        entries: entries,
        holdings: const [],
        budgets: const [],
        recurring: [rent()],
      );

  List<DateTime> rentDays(Ledger ledger) => [
    for (final e in ledger.entries.all)
      if (e.recurring == rentId) e.date,
  ]..sort();

  test('months missed while away are listed first, then booked each on '
      'its day once confirmed (D61)', () {
    // Opened in June, July and August, then not until 11/13.
    final ledger = book(
      today: DateTime.utc(2026, 11, 13),
      entries: [booked(6), booked(7), booked(8)],
    );
    final due = ledger.recurringCommands.bookDue();
    expect(due.booked, 0, reason: 'more than one period: asked first');
    final held = due.held.single;
    expect(held.item.id, rentId);
    expect(held.confirmable, isTrue);
    expect(held.days, [
      for (final m in [9, 10, 11]) DateTime.utc(2026, m, 1),
    ]);
    expect(ledger.recurringCommands.bookDays(held.item, held.days), 3);
    expect(rentDays(ledger), [
      for (final m in [6, 7, 8, 9, 10, 11]) DateTime.utc(2026, m, 1),
    ]);
    final again = ledger.recurringCommands.bookDue();
    expect(again.booked, 0, reason: 'booked once only');
    expect(again.held, isEmpty);
  });

  test('a new item books this month only, not every month since it began', () {
    final ledger = book(today: DateTime.utc(2026, 11, 13), entries: const []);
    expect(ledger.recurringCommands.bookDue().booked, 1);
    expect(rentDays(ledger), [DateTime.utc(2026, 11, 1)]);
  });

  test('a deleted booking is a period skipped: it is not booked again', () {
    final ledger = book(
      today: DateTime.utc(2026, 11, 13),
      entries: [booked(10), booked(11)],
    );
    expect(ledger.recurringCommands.bookDue().booked, 0);
    ledger.entryCommands.remove('r11');
    expect(ledger.recurring.all.single.skipped, {DateTime.utc(2026, 11, 1)});
    expect(
      ledger.recurringCommands.bookDue().booked,
      0,
      reason: 'deleted stays deleted',
    );
    expect(ledger.recurringService.due, isEmpty);
  });

  test('putting it back, or 恢復, takes the skip away again', () {
    final ledger = book(
      today: DateTime.utc(2026, 11, 13),
      entries: [booked(10), booked(11)],
    );
    final removed = ledger.entryCommands.removeAll(['r11']);
    expect(ledger.recurring.all.single.skipped, isNotEmpty);
    expect(ledger.entryCommands.restoreAll(removed), isTrue);
    expect(ledger.recurring.all.single.skipped, isEmpty);
    expect(
      ledger.recurringCommands.bookDue().booked,
      0,
      reason: 'November is back, booked',
    );

    ledger.entryCommands.remove('r11');
    ledger.recurringCommands.unskip(
      ledger.recurring.all.single,
      DateTime.utc(2026, 11, 1),
    );
    expect(
      ledger.recurringCommands.bookDue().booked,
      1,
      reason: '恢復: booked again',
    );
    expect(rentDays(ledger).last, DateTime.utc(2026, 11, 1));
  });

  test('skipped days are kept with the item', () {
    final item = rent(
      skipped: {DateTime.utc(2026, 9, 1), DateTime.utc(2026, 7, 1)},
    );
    final back = recurringFromJson(recurringToJson(item));
    expect(back.skipped, item.skipped);
    expect(recurringToJson(rent()).containsKey('skipped'), isFalse);
  });
}
