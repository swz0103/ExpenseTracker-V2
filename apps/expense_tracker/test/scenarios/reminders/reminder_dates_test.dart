import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/reminders/model/reminder_alerts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/src/features/reminders/ui/reminders_section.dart'
    show reminderBookOf;

/// Reminders and notifications where days and months turn over: the end
/// of a month, a short February, a leap year, the end of a year, and a
/// card payment two days into the next month.
void main() {
  const bank = Account('bank', '銀行', AccountKind.bank, 50000);

  Recurring monthly(String id, int day, {DateTime? start}) => Recurring(
    id: id,
    name: id,
    amount: 100,
    day: day,
    account: 'bank',
    category: '其他',
    start: start ?? DateTime.utc(2025, 1, day),
  );

  Ledger book(
    DateTime today, {
    List<Recurring> recurring = const [],
    List<Account> accounts = const [bank],
    List<Entry> entries = const [],
  }) => Ledger(
    today: today,
    accounts: accounts,
    categories: [],
    entries: entries,
    holdings: const [],
    budgets: const [],
    recurring: recurring,
  );

  List<DateTime> days(Ledger ledger, {int ahead = 60}) => [
    for (final r in reminderBookOf(ledger).reminders(days: ahead)) r.day,
  ];

  test('an item on the 31st falls on the last day of shorter months', () {
    final ledger = book(
      DateTime.utc(2026, 1, 20),
      recurring: [monthly('rent', 31)],
    );
    expect(days(ledger, ahead: 70), [
      DateTime.utc(2026, 1, 31),
      DateTime.utc(2026, 2, 28),
      DateTime.utc(2026, 3, 31),
    ]);
  });

  test('February has a 29th in a leap year', () {
    final ledger = book(
      DateTime.utc(2028, 2, 10),
      recurring: [monthly('rent', 30)],
    );
    expect(days(ledger, ahead: 30), [DateTime.utc(2028, 2, 29)]);
  });

  test('the year turns over: December 20 reminds of January 5', () {
    final ledger = book(
      DateTime.utc(2026, 12, 20),
      recurring: [monthly('netflix', 5)],
    );
    expect(days(ledger, ahead: 30), [DateTime.utc(2027, 1, 5)]);
  });

  test('today counts, yesterday does not', () {
    final ledger = book(
      DateTime.utc(2026, 3, 5),
      recurring: [monthly('netflix', 5), monthly('gym', 4)],
    );
    expect(days(ledger, ahead: 30), [
      DateTime.utc(2026, 3, 5),
      DateTime.utc(2026, 4, 4),
    ]);
  });

  test('the last day of the range counts, the day after does not', () {
    final ledger = book(
      DateTime.utc(2026, 3, 1),
      recurring: [monthly('a', 31), monthly('b', 1)],
    );
    // 30 days from March 1 is March 31.
    expect(days(ledger, ahead: 30), [
      DateTime.utc(2026, 3, 1),
      DateTime.utc(2026, 3, 31),
    ]);
  });

  test('every other month keeps its months across the year', () {
    final ledger = book(
      DateTime.utc(2026, 11, 20),
      recurring: [
        Recurring(
          id: 'water',
          name: '水費',
          amount: 300,
          day: 15,
          account: 'bank',
          category: '其他',
          every: 2,
          start: DateTime.utc(2026, 1, 15),
        ),
      ],
    );
    // January, March … November: the next after November is January.
    expect(days(ledger, ahead: 120), [
      DateTime.utc(2027, 1, 15),
      DateTime.utc(2027, 3, 15),
    ]);
  });

  test('a weekly item runs on into the next month', () {
    final ledger = book(
      DateTime.utc(2026, 3, 25),
      recurring: [
        Recurring(
          id: 'weekly',
          name: '早餐',
          amount: 80,
          day: 1,
          account: 'bank',
          category: '其他',
          unit: RepeatUnit.week,
          start: DateTime.utc(2026, 3, 2),
        ),
      ],
    );
    expect(days(ledger, ahead: 14), [
      DateTime.utc(2026, 3, 30),
      DateTime.utc(2026, 4, 6),
    ]);
  });

  group('notifications', () {
    final on = Preferences()..update(dueAlerts: true);

    test('a payment on the 1st warns two days before, in the month before', () {
      const card = Account(
        'card',
        '信用卡',
        AccountKind.card,
        0,
        closingDay: 15,
        dueDay: 1,
      );
      final ledger = book(
        DateTime.utc(2026, 3, 20),
        accounts: const [bank, card],
        entries: [
          Entry(
            id: 'shoes',
            date: DateTime.utc(2026, 3, 10),
            type: EntryType.expense,
            amount: 1000,
            account: 'card',
            category: '購物',
          ),
        ],
      );
      final alerts = alertsFor(
        reminderBookOf(ledger),
        on,
        DateTime(2026, 3, 20, 8),
      );
      expect(
        [for (final a in alerts) (a.at, a.title)],
        [
          (DateTime(2026, 3, 30, 9), '2 天後 繳卡費：信用卡 1,000'),
          (DateTime(2026, 4, 1, 9), '繳卡費：信用卡 1,000'),
        ],
      );
    });

    test('the early warning crosses the year as well', () {
      const card = Account(
        'card',
        '信用卡',
        AccountKind.card,
        0,
        closingDay: 15,
        dueDay: 1,
      );
      final ledger = book(
        DateTime.utc(2026, 12, 20),
        accounts: const [bank, card],
        entries: [
          Entry(
            id: 'gift',
            date: DateTime.utc(2026, 12, 10),
            type: EntryType.expense,
            amount: 2000,
            account: 'card',
            category: '購物',
          ),
        ],
      );
      final alerts = alertsFor(
        reminderBookOf(ledger),
        on,
        DateTime(2026, 12, 20, 8),
      );
      expect(
        [for (final a in alerts) a.at],
        [DateTime(2026, 12, 30, 9), DateTime(2027, 1, 1, 9)],
      );
    });

    test('nine o\'clock today is still told at ten (the phone posts it at '
        'once), and tomorrow\'s at its time', () {
      final ledger = book(
        DateTime.utc(2026, 1, 31),
        recurring: [monthly('rent', 31), monthly('phone', 1)],
      );
      final at9 = alertsFor(
        reminderBookOf(ledger),
        on,
        DateTime(2026, 1, 31, 8, 59),
      );
      final at10 = alertsFor(
        reminderBookOf(ledger),
        on,
        DateTime(2026, 1, 31, 10),
      );
      expect([for (final a in at9) a.at].take(2), [
        DateTime(2026, 1, 31, 9),
        DateTime(2026, 2, 1, 9),
      ]);
      // F48: today's 9:00 went by before the plan was written; within a
      // due date's grace it is still handed over, to be posted at once.
      expect([for (final a in at10) a.at].take(2), [
        DateTime(2026, 1, 31, 9),
        DateTime(2026, 2, 1, 9),
      ]);
    });

    test('the nudge runs on into the next month', () {
      final preferences = Preferences()
        ..update(dailyNudge: true, nudgeHour: 21, nudgeMinute: 30);
      final ledger = book(DateTime.utc(2026, 2, 26));
      final alerts = alertsFor(
        reminderBookOf(ledger),
        preferences,
        DateTime(2026, 2, 26, 12),
      );
      // 62 days of the plan: Feb 26 and the 61 days after it.
      expect(
        [for (final a in alerts) a.at],
        [for (var d = 0; d < 62; d++) DateTime(2026, 2, 26 + d, 21, 30)],
      );
      // Feb 26 + 61 days: 2 more in February, 31 in March, 28 in April.
      expect(alerts.last.at, DateTime(2026, 4, 28, 21, 30));
    });

    test('no nudge today once something is recorded', () {
      final preferences = Preferences()..update(dailyNudge: true);
      final today = DateTime.utc(2026, 4, 30);
      final ledger = book(
        today,
        entries: [
          Entry(
            id: 'lunch',
            date: today,
            type: EntryType.expense,
            amount: 120,
            account: 'bank',
            category: '飲食',
          ),
        ],
      );
      final alerts = alertsFor(
        reminderBookOf(ledger),
        preferences,
        DateTime(2026, 4, 30, 8),
      );
      expect(alerts.first.at, DateTime(2026, 5, 1, 21));
      // The 62 days of the plan less today.
      expect(alerts, hasLength(61));
    });
  });
}
