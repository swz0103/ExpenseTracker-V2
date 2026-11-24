import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/src/features/reminders/ui/reminders_section.dart'
    show reminderBookOf;

void main() {
  test('what falls due goes to the calendar, soonest first', () {
    const card = Account(
      'card',
      '信用卡',
      AccountKind.card,
      0,
      closingDay: 25,
      dueDay: 10,
    );
    final ledger = Ledger(
      today: DateTime.utc(2026, 4, 3),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 50000), card],
      categories: [],
      entries: [
        Entry(
          id: 'shoes',
          date: DateTime.utc(2026, 3, 20),
          type: EntryType.expense,
          amount: 1000,
          account: 'card',
          category: '購物',
        ),
      ],
      holdings: const [],
      budgets: const [],
      recurring: const [
        Recurring(
          id: 'netflix',
          name: 'Netflix',
          amount: 390,
          day: 5,
          account: 'bank',
          category: '訂閱服務',
        ),
        Recurring(
          id: 'gym',
          name: '健身房',
          amount: 1200,
          day: 8,
          account: 'bank',
          category: '其他',
          active: false,
        ),
      ],
    );
    final found = reminderBookOf(ledger).reminders();
    final titles = [for (final r in found) r.title];
    expect(titles, ['扣款：Netflix 390', '繳卡費：信用卡 1,000', '扣款：Netflix 390']);
    expect(found[1].day, DateTime.utc(2026, 4, 10));
    expect(found[1].daysAhead, 2);
    expect(found.last.day, DateTime.utc(2026, 5, 5));
    expect({for (final r in found) r.key}, hasLength(3));
  });

  test('D68: the notifications and the calendar read one window, an '
      'overdue day still unbooked in it', () {
    final ledger = Ledger(
      today: DateTime.utc(2026, 4, 3),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 50000)],
      categories: [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: [
        Recurring(
          id: 'netflix',
          name: 'Netflix',
          amount: 390,
          day: 1,
          account: 'bank',
          category: '訂閱服務',
          start: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
    final book = reminderBookOf(ledger);
    // 7 days back from April 3: March 27.
    expect(book.windowStart, DateTime.utc(2026, 3, 27));
    final due = book.dueReminders();
    // April 1 is two days overdue and in it; May 1 and June 1 ahead.
    expect(
      [for (final r in due) r.day],
      [
        DateTime.utc(2026, 4, 1),
        DateTime.utc(2026, 5, 1),
        DateTime.utc(2026, 6, 1),
      ],
    );
  });
}
