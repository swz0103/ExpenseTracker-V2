import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart' show UtcInstant;
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/time/app_clock.dart';
import 'package:expense_tracker/src/features/reminders/model/reminder_alerts.dart';
import 'package:expense_tracker/src/features/reminders/model/reminder_rules.dart';
import 'package:expense_tracker/src/features/reminders/ui/reminders_section.dart'
    show reminderBookOf;
import 'package:flutter_test/flutter_test.dart';

/// The plan the phone is handed: what is due, from as far back as a due
/// date is still told to the horizon, and when it is handed again.
void main() {
  // Monday 2026-11-23.
  final today = DateTime.utc(2026, 11, 23);
  const bank = Account('bank', '銀行', AccountKind.bank, 50000);
  const card = Account(
    'card',
    '玉山卡',
    AccountKind.card,
    0,
    closingDay: 5,
    dueDay: 20,
  );

  Recurring monthly(String id, int day) => Recurring(
    id: id,
    name: id,
    amount: 300,
    day: day,
    account: 'bank',
    category: '其他',
    start: DateTime.utc(2026, 1, day),
  );

  Ledger book({
    List<Recurring> recurring = const [],
    List<Entry> entries = const [],
  }) => Ledger(
    today: today,
    accounts: const [bank, card],
    categories: [],
    entries: entries,
    holdings: const [],
    budgets: const [],
    recurring: recurring,
  );

  final due = Preferences()..update(dueAlerts: true);

  group(
    'F48: what is due today or overdue is told when the plan is written',
    () {
      test('a day 3 days overdue is handed over (posted at once), one 8 days '
          'overdue is past its 7 days of grace', () {
        final ledger = book(
          recurring: [monthly('gym', 20), monthly('rent', 15)],
        );
        final alerts = alertsFor(
          reminderBookOf(ledger),
          due,
          DateTime(2026, 11, 23, 10),
        );
        expect(
          [for (final a in alerts) (a.at, a.title)],
          [
            // Nov 20 9:00 is 3 days 1 hour ago: within 7 days.
            (DateTime(2026, 11, 20, 9), '扣款：gym 300'),
            (DateTime(2026, 12, 15, 9), '扣款：rent 300'),
            (DateTime(2026, 12, 20, 9), '扣款：gym 300'),
            // Nov 23 + 62 days is Jan 24: Jan 15 and 20 are within it.
            (DateTime(2027, 1, 15, 9), '扣款：rent 300'),
            (DateTime(2027, 1, 20, 9), '扣款：gym 300'),
          ],
        );
        // Nov 15 9:00 was 8 days 1 hour ago: not told.
        expect(alerts.first.kind, ReminderKind.due);
        expect(alerts.first.confirms, ('gym', DateTime.utc(2026, 11, 20)));
      });

      test('a card payment overdue and unpaid is told, its early warning '
          'is not', () {
        final ledger = book(
          entries: [
            Entry(
              id: 'shoes',
              date: DateTime.utc(2026, 10, 20),
              type: EntryType.expense,
              amount: 1000,
              account: 'card',
              category: '購物',
            ),
          ],
        );
        final alerts = alertsFor(
          reminderBookOf(ledger),
          due,
          DateTime(2026, 11, 23, 10),
        );
        // The statement closed on Nov 5 and was due on Nov 20 (a Friday);
        // its early warning on Nov 18 is a kind not told late.
        expect(
          [for (final a in alerts) (a.at, a.kind, a.title)],
          [(DateTime(2026, 11, 20, 9), ReminderKind.due, '繳卡費：玉山卡 1,000')],
        );
      });

      test('the nudge passed today is not told late', () {
        final nudge = Preferences()..update(dailyNudge: true, nudgeHour: 9);
        final alerts = alertsFor(
          reminderBookOf(book()),
          nudge,
          DateTime(2026, 11, 23, 10),
        );
        expect(alerts.first.at, DateTime(2026, 11, 24, 9));
        expect(alerts.first.kind, ReminderKind.nudge);
      });
    },
  );

  test('each alert has an id that stays from one plan to the next', () {
    final ledger = book(recurring: [monthly('gym', 20)]);
    List<String> ids(DateTime now) => [
      for (final a in alertsFor(reminderBookOf(ledger), due, now)) a.id,
    ];
    expect(
      ids(DateTime(2026, 11, 23, 10)).first,
      'due|due:r:gym:2026-11-20|2026-11-20',
    );
    expect(ids(DateTime(2026, 11, 23, 10)), ids(DateTime(2026, 11, 23, 11)));
  });

  test('the plan holds at most so many, soonest first', () {
    final nudge = Preferences()..update(dailyNudge: true, dueAlerts: true);
    final ledger = book(
      recurring: [
        for (var d = 1; d <= 28; d++) ...[monthly('a$d', d), monthly('b$d', d)],
      ],
    );
    final alerts = alertsFor(
      reminderBookOf(ledger),
      nudge,
      DateTime(2026, 11, 23, 8),
    );
    expect(alerts, hasLength(160));
    expect(alerts.first.at, DateTime(2026, 11, 16, 9));
    // Two items a day at 9:00 and, from today, the nudge at 21:00:
    // Nov 16-22 give 14, Nov 23-28 give 18, Nov 29-30 give 2 nudges,
    // Dec 1-28 give 84, Dec 29-31 give 3 nudges: 121; Jan 1-13 give 39
    // more, 160, the last the nudge of Jan 13.
    expect(alerts.last.at, DateTime(2027, 1, 13, 21));
  });

  test('a plan is the same as another saying the same', () {
    final ledger = book(recurring: [monthly('gym', 20)]);
    final now = DateTime(2026, 11, 23, 10);
    final a = planFor(reminderBookOf(ledger), due, now);
    final b = planFor(reminderBookOf(ledger), due, now);
    expect(a.sameAs(b), isTrue);
    expect(a.sameAs(null), isFalse);
    final exact = Preferences()..update(dueAlerts: true, exactReminders: true);
    expect(a.sameAs(planFor(reminderBookOf(ledger), exact, now)), isFalse);
    expect(a.wanted, {
      'due:r:gym:2026-11-20',
      'due:r:gym:2026-12-20',
      'due:r:gym:2027-1-20',
    });
  });

  group('Notifier', () {
    setUp(
      () => AppClock.use(FixedClock(UtcInstant(DateTime.utc(2026, 11, 23, 2)))),
    );
    tearDown(AppClock.reset);

    Ledger cardBook() => book(
      entries: [
        Entry(
          id: 'shoes',
          date: DateTime.utc(2026, 11, 10),
          type: EntryType.expense,
          amount: 1000,
          account: 'card',
          category: '購物',
        ),
      ],
    );

    test(
      'F81: paying a card plans again at once, without its notice',
      () async {
        // Spent Nov 10, after the Nov 5 closing: due on the statement that
        // closes Dec 5, so nothing is owed on the last one; one closed
        // statement, the one of Nov 5, owes nothing.
        final ledger = cardBook();
        final port = _Port();
        final notifier = Notifier(port, due)..follow(reminderBookOf(ledger));
        await notifier.idle;
        final before = port.plans.length;
        expect(before, 1);

        // A purchase of the last statement, then paying it.
        ledger.entryCommands.add(
          Entry(
            id: 'old',
            date: DateTime.utc(2026, 11, 1),
            type: EntryType.expense,
            amount: 500,
            account: 'card',
            category: '購物',
          ),
        );
        await notifier.idle;
        expect(port.plans.length, before + 1);
        expect(port.plans.last.wanted, contains('due:c:card:2026-11-5'));

        ledger.entryCommands.add(
          Entry(
            id: 'pay',
            date: today,
            type: EntryType.transfer,
            amount: 500,
            account: 'bank',
            to: 'card',
            category: '',
          ),
        );
        await notifier.idle;
        expect(port.plans.length, before + 2);
        expect(port.plans.last.wanted, isNot(contains('due:c:card:2026-11-5')));
        notifier.stop();
      },
    );

    test('REM-04: a new closing price plans nothing again; a change '
        'that leaves the plan as it was is not handed over', () async {
      final ledger = cardBook();
      final port = _Port();
      final notifier = Notifier(port, due)..follow(reminderBookOf(ledger));
      await notifier.idle;
      expect(port.plans, hasLength(1));

      ledger.holdingCommands.setMarket(
        holdings: const [],
        moves: const {},
        rates: const {'USD': 32.0},
      );
      await notifier.idle;
      expect(port.plans, hasLength(1));

      // A coffee in cash: the book changed, what is due did not.
      ledger.entryCommands.add(
        Entry(
          id: 'coffee',
          date: today,
          type: EntryType.expense,
          amount: 65,
          account: 'bank',
          category: '飲食',
        ),
      );
      await notifier.idle;
      expect(port.plans, hasLength(1));
      notifier.stop();
    });
  });
}

/// The phone's notifications, keeping each plan handed over.
final class _Port implements NotifyPort {
  final plans = <ReminderPlan>[];

  @override
  Future<bool> access() async => true;

  @override
  Future<void> schedule(ReminderPlan plan) async => plans.add(plan);

  @override
  Future<void> test({required bool exact}) async {}

  @override
  Future<void> post(Alert alert, int id) async {}

  @override
  Future<ReminderStatus> status() async =>
      (notifications: true, exact: true, battery: true);

  @override
  Future<void> openExactSettings() async {}

  @override
  Future<void> openBatterySettings() async {}
}
