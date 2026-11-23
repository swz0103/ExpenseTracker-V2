// Work package 3.4: reminders agree with the ledger.

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/reminders/ui/reminders_section.dart'
    show reminderBookOf;
import 'package:flutter_test/flutter_test.dart';

import '../baseline/baseline_ledger.dart';

void main() {
  test('REM-05: a day let go of is not reminded about', () {
    final gym = Recurring(
      id: 'gym',
      name: '健身房',
      amount: 1200,
      day: 25,
      account: 'bank',
      category: '飲食',
      start: day(2026, 1, 25),
      skipped: {day(2026, 11, 25)},
    );
    final ledger = ledgerOf(
      today: day(2026, 11, 22),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
      recurring: [gym],
    );
    final reminders = reminderBookOf(ledger).reminders();
    // Nov 25 was skipped: no reminder is made for it.
    expect([
      for (final r in reminders)
        if (r.title.contains('健身房') && r.day == day(2026, 11, 25)) r,
    ], isEmpty);
  });
}
