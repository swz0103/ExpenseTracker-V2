import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/reminders/model/reminder_alerts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/src/features/reminders/ui/reminders_section.dart'
    show reminderBookOf;

/// Keeps nothing.
final class _Nowhere implements LedgerDataSource {
  @override
  Future<void> keep(WriteBatch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

/// Notifications in memory.
final class _Port implements NotifyPort {
  final posted = <Alert>[];

  @override
  Future<bool> access() async => true;

  @override
  Future<void> schedule(ReminderPlan plan) async {}

  @override
  Future<void> test({required bool exact}) async {}

  @override
  Future<void> post(Alert alert, int id) async => posted.add(alert);

  @override
  Future<ReminderStatus> status() async =>
      (notifications: true, exact: true, battery: true);

  @override
  Future<void> openExactSettings() async {}

  @override
  Future<void> openBatterySettings() async {}
}

void main() {
  final day = DateTime.utc(2026, 10, 20);

  Ledger book() => Ledger(
    today: day,
    accounts: const [Account('cash', '現金', AccountKind.cash, 50000)],
    categories: [Category('飲食', 'food', 0xFF5C9A83)],
    entries: const [],
    holdings: const [],
    budgets: const [Budget('飲食', 1000)],
    recurring: const [],
    dataSource: _Nowhere(),
  );

  Entry spend(String id, int amount) => Entry(
    id: id,
    date: day,
    type: EntryType.expense,
    amount: amount,
    account: 'cash',
    category: '飲食',
  );

  test('a budget warns once at its share and once when used up', () async {
    final ledger = book();
    final preferences = Preferences()..update(budgetAlerts: true);
    final port = _Port();
    final notifier = Notifier(port, preferences);

    ledger.entryCommands.add(spend('a', 700));
    await notifier.postBudgets(reminderBookOf(ledger));
    expect(port.posted, isEmpty);

    ledger.entryCommands.add(spend('b', 150));
    await notifier.postBudgets(reminderBookOf(ledger));
    expect([for (final a in port.posted) a.title], ['「飲食」預算已用 85%']);
    expect(port.posted.single.text, '還剩 150');
    expect(
      port.posted.single.tag,
      'budget:96c2539e-3dd4-5a29-becf-9344600ca2a9',
    );
    // Not again while it stays there.
    ledger.entryCommands.add(spend('c', 50));
    await notifier.postBudgets(reminderBookOf(ledger));
    expect(port.posted, hasLength(1));
    expect(
      wantedTags(reminderBookOf(ledger), preferences),
      // The budget by an id, never its name (review 34): NameId of 飲食.
      contains('budget:96c2539e-3dd4-5a29-becf-9344600ca2a9'),
    );

    ledger.entryCommands.add(spend('d', 200));
    await notifier.postBudgets(reminderBookOf(ledger));
    expect(port.posted.last.title, '「飲食」預算已超支');
    expect(port.posted.last.text, '已用 1,100，超出 100');
    await notifier.postBudgets(reminderBookOf(ledger));
    expect(port.posted, hasLength(2));
  });

  test('none when budget notifications are off', () {
    final ledger = book()..entryCommands.add(spend('a', 2000));
    final preferences = Preferences()..update(budgetAlerts: false);
    expect(budgetCrossings(reminderBookOf(ledger), preferences), isEmpty);
  });
}
