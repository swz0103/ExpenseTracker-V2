import 'dart:convert';
import 'dart:typed_data';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/reminders/model/inbox_apply.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';

void main() {
  Recurring item(String id, int day, {bool active = true}) => Recurring(
    id: id,
    name: id,
    amount: 500,
    day: day,
    account: 'bank',
    category: '居家',
    active: active,
    start: DateTime.utc(2026, 10, day),
  );

  Ledger book() => Ledger(
    today: DateTime.utc(2026, 10, 12),
    accounts: const [Account('bank', '銀行', AccountKind.bank, 50000)],
    categories: const [Category('居家', 'home', Color(0xFF5B8DB0))],
    entries: const [],
    holdings: const [],
    budgets: const [],
    recurring: [item('rent', 5), item('gym', 10, active: false)],
  );

  InboxItem confirm(String id, String day) => (
    name: '$id-$day.json',
    plain: Uint8List.fromList(
      utf8.encode('{"kind":"confirm","recurring":"$id","day":"$day"}'),
    ),
  );

  test('a confirmation books its day once; the rest is listed', () {
    final ledger = book();
    final outcome = applyInbox(ledger, [
      confirm('rent', '2026-10-05'),
      // Tapped twice: the day is booked already, let go.
      confirm('rent', '2026-10-05'),
      confirm('gym', '2026-10-10'),
      confirm('gone', '2026-10-07'),
      (name: 'old.json', plain: null),
    ]);
    expect(outcome.booked, 1);
    final rent = ledger.entries.single;
    expect((rent.recurring, rent.date), ('rent', DateTime.utc(2026, 10, 5)));
    expect(outcome.review, hasLength(3));
    expect(outcome.review[0], contains('已暫停'));
    expect(outcome.review[1], contains('已刪除'));
    expect(outcome.review[2], contains('1 則'));
  });
}
