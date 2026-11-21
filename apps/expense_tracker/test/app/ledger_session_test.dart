import 'dart:convert';
import 'dart:typed_data';

import 'package:expense_tracker/src/app/ledger_session.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';

/// Opening a ledger: load it, apply the inbox, check it, book what is
/// due, each step on its own so one failing leaves the others running.
void main() {
  final today = DateTime.utc(2026, 10, 12);

  Recurring item(String id, int day, {bool auto = false}) => Recurring(
    id: id,
    name: id,
    amount: 500,
    day: day,
    account: 'bank',
    category: '居家',
    auto: auto,
    start: DateTime.utc(2026, 10, day),
  );

  Ledger book({List<Recurring>? recurring, List<Entry> entries = const []}) =>
      Ledger(
        today: today,
        accounts: const [Account('bank', '銀行', AccountKind.bank, 50000)],
        categories: [Category('居家', 'home', 0xFF5B8DB0)],
        entries: entries,
        holdings: const [],
        budgets: const [],
        recurring: recurring ?? [item('rent', 5)],
      );

  InboxItem confirm(String id, String day) => (
    name: '$id-$day.json',
    plain: Uint8List.fromList(
      utf8.encode('{"kind":"confirm","recurring":"$id","day":"$day"}'),
    ),
  );

  /// An inbox holding [items], which notes what was taken out.
  (Future<InboxSource> Function(), List<String>) inbox(List<InboxItem> items) {
    final removed = <String>[];
    return (
      () async => (
        read: () async => items,
        remove: (String name) async => removed.add(name),
      ),
      removed,
    );
  }

  List<String> logged(void Function() run) {
    final before = ErrorLog.instance.entries.length;
    run();
    final all = ErrorLog.instance.entries;
    return [for (final (_, text) in all.take(all.length - before)) text];
  }

  test('without an inbox the book opens with nothing to tell', () async {
    final ledger = book();
    final start = await LedgerSession(load: () async => ledger).open();
    expect(start.ledger, same(ledger));
    expect(start.inbox, isNull);
    expect(start.booked, 0);
  });

  test('the inbox books its confirmations and is emptied', () async {
    final ledger = book();
    final (open, removed) = inbox([confirm('rent', '2026-10-05')]);
    final start = await LedgerSession(
      load: () async => ledger,
      inbox: open,
    ).open();
    expect(start.inbox?.booked, 1);
    expect(ledger.entries.all.single.recurring, 'rent');
    expect(removed, ['rent-2026-10-05.json']);
  });

  test('an empty inbox tells nothing', () async {
    final (open, removed) = inbox(const []);
    final start = await LedgerSession(
      load: () async => book(),
      inbox: open,
    ).open();
    expect(start.inbox, isNull);
    expect(removed, isEmpty);
  });

  test('an inbox that cannot be opened is logged, and the book still opens '
      'and books what is due', () async {
    final ledger = book(recurring: [item('rent', 5, auto: true)]);
    final before = ErrorLog.instance.entries.length;
    final start = await LedgerSession(
      load: () async => ledger,
      inbox: () async => throw StateError('sealed for another ledger'),
    ).open();
    expect(start.inbox, isNull);
    expect(start.booked, 1);
    expect(ErrorLog.instance.entries.length, before + 1);
    expect(ErrorLog.instance.entries.first.$2, contains('收件匣'));
  });

  test('items marked to book themselves are booked once their day came', () {
    final ledger = book(
      recurring: [item('rent', 5, auto: true), item('gym', 20, auto: true)],
    );
    final session = LedgerSession(load: () async => ledger);
    expect(session.bookDue(ledger), 1);
    // Booked once: coming back the same day books nothing more.
    expect(session.bookDue(ledger), 0);
  });

  test('a record naming an account the book lacks is logged once a kind', () {
    final orphan = Entry(
      id: 'e1',
      date: today,
      type: EntryType.expense,
      amount: 100,
      account: 'gone',
      category: '居家',
    );
    final ledger = book(entries: [orphan, orphan.withId('e2')]);
    final notes = logged(
      () => LedgerSession(load: () async => ledger).checkIntegrity(ledger),
    );
    expect(notes.where((n) => n.contains('帳本健檢')), hasLength(1));
  });
}
