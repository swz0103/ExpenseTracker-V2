import 'dart:io';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/reminders/model/calendar_sync.dart';
import 'package:expense_tracker/src/features/reminders/model/reminders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/src/features/reminders/ui/reminders_section.dart'
    show reminderBookOf;

import '../../../support/fake_calendar.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('calendar-'));
  tearDown(() => directory.deleteSync(recursive: true));

  CalendarEvent event(
    String key, {
    int? id,
    String title = '扣款：Netflix',
    int day = 5,
  }) => CalendarEvent(
    id: id,
    key: key,
    title: title,
    note: '定期交易',
    start: DateTime(2026, 12, day, 9),
    remind: const [0],
  );

  group('calendarChanges', () {
    test('leaves the same alone, changes in place, takes away and writes '
        'by key', () {
      final changes = calendarChanges(
        [
          event('same', id: 1),
          event('changed', id: 2, title: '扣款：舊名'),
          event('gone', id: 3),
          event('twice', id: 4),
          event('twice', id: 5),
        ],
        [event('same'), event('changed'), event('twice'), event('new')],
      );
      expect([for (final e in changes.insert) e.key], ['new']);
      expect(
        [for (final e in changes.update) (e.id, e.key, e.title)],
        [(2, 'changed', '扣款：Netflix')],
      );
      // 5 is the second event of one key; 3 is no longer wanted.
      expect(changes.delete, [5, 3]);
    });

    test('nothing to change when the calendar holds what is wanted', () {
      expect(
        calendarChanges([event('a', id: 1)], [event('a')]).isEmpty,
        isTrue,
      );
      expect(calendarChanges(const [], const []).isEmpty, isTrue);
    });

    test('a reminder moved to another day is changed, not written again', () {
      final changes = calendarChanges(
        [event('a', id: 7, day: 5)],
        [event('a', day: 6)],
      );
      expect(changes.insert, isEmpty);
      expect(changes.delete, isEmpty);
      expect(changes.update.single.id, 7);
      expect(changes.update.single.start, DateTime(2026, 12, 6, 9));
    });
  });

  test('an event is at 9:00 on its day, reminding then and its days '
      'ahead before, with no amount unless asked', () {
    final reminder = Reminder(
      key: 'c:card:2026-11-25',
      day: DateTime.utc(2026, 12, 10),
      title: '繳卡費：玉山卡 12,345',
      bare: '繳卡費：玉山卡',
      note: '11/25 結帳的帳單',
      daysAhead: 2,
    );
    final plain = CalendarEvent.of(reminder, amounts: false);
    expect(plain.title, '繳卡費：玉山卡');
    expect(plain.start, DateTime(2026, 12, 10, 9));
    // 2 days before is 2 × 24 × 60 = 2,880 minutes.
    expect(plain.remind, [0, 2880]);
    expect(CalendarEvent.of(reminder, amounts: true).title, '繳卡費：玉山卡 12,345');
  });

  test('what falls due goes to the chosen calendar only', () async {
    final ledger = demoLedger();
    final port = FakeCalendars(
      choices: const [
        CalendarChoice(1, '個人', 'me@example.com'),
        CalendarChoice(2, '家庭', 'me@example.com'),
      ],
    );
    final sync = CalendarSync(port, directory);
    expect(await sync.sync(reminderBookOf(ledger)), isNull);

    await sync.choose(
      const CalendarChoice(1, '個人', 'me'),
      reminderBookOf(ledger),
    );
    expect(sync.chosen, (1, '個人'));
    final written = await sync.sync(reminderBookOf(ledger));
    expect(written, reminderBookOf(ledger).reminders().length);
    expect(written, greaterThan(0));

    // Moving to another calendar takes them off the first.
    await sync.choose(
      const CalendarChoice(2, '家庭', 'me'),
      reminderBookOf(ledger),
    );
    expect(port.written(1), isEmpty);
    await sync.sync(reminderBookOf(ledger));
    expect(port.written(2), isNotEmpty);

    // Chosen again after a restart of the app.
    expect(CalendarSync(port, directory).chosen, (2, '家庭'));

    expect(await sync.forget(reminderBookOf(ledger)), isTrue);
    expect(port.written(2), isEmpty);
    expect(sync.chosen, isNull);
  });

  test('REM-04: a sync with nothing changed writes nothing; a change '
      'touches only its event, which keeps its id', () async {
    final ledger = demoLedger();
    final port = FakeCalendars();
    final sync = CalendarSync(port, directory);
    await sync.choose(
      const CalendarChoice(1, '工作', ''),
      reminderBookOf(ledger),
    );
    await sync.sync(reminderBookOf(ledger));
    expect(port.applied, hasLength(1));
    final before = {for (final e in port.written(1)) e.key: e.id};

    // A coffee recorded on cash changes no reminder.
    ledger.entryCommands.add(
      Entry(
        id: 'coffee',
        date: ledger.today,
        type: EntryType.expense,
        amount: 65,
        account: ledger.accounts.all
            .firstWhere((a) => a.kind == AccountKind.cash)
            .id,
        category: '飲食',
      ),
    );
    await sync.sync(reminderBookOf(ledger));
    expect(port.applied, hasLength(1), reason: 'nothing to change');

    // A recurring item renamed: only its own events change, in place.
    final due = reminderBookOf(ledger)
        .reminders()
        .firstWhere((r) => r.recurring != null);
    final item = ledger.recurring.all.firstWhere((r) => r.id == due.recurring);
    ledger.recurringCommands.saveRecurring(item.copyWith(name: '改名了'));
    await sync.sync(reminderBookOf(ledger));
    expect(port.applied, hasLength(2));
    final (_, changes) = port.applied.last;
    expect(changes.insert, isEmpty);
    expect(changes.delete, isEmpty);
    expect(changes.update, isNotEmpty);
    for (final e in changes.update) {
      expect(e.key, startsWith('r:${item.id}:'));
      expect(e.id, before[e.key]);
    }
  });

  test('REM-05: calendar access taken away still lets the link go', () async {
    final ledger = demoLedger();
    final port = FakeCalendars();
    final sync = CalendarSync(port, directory);
    await sync.choose(
      const CalendarChoice(1, '工作', ''),
      reminderBookOf(ledger),
    );
    await sync.sync(reminderBookOf(ledger));
    port.revoked = true;
    expect(await sync.forget(reminderBookOf(ledger)), isFalse);
    expect(sync.chosen, isNull);
    expect(CalendarSync(port, directory).chosen, isNull);
  });

  test('a calendar out of reach is noted, not thrown, and told', () async {
    final ledger = demoLedger();
    final port = FakeCalendars();
    var told = 0;
    final sync = CalendarSync(port, directory, failed: () => told++);
    await sync.choose(
      const CalendarChoice(1, '工作', ''),
      reminderBookOf(ledger),
    );
    expect(told, 0);
    port.reachable = false;
    expect(await sync.sync(reminderBookOf(ledger)), isNull);
    // D84: the person hears of it (once a run: QuietFailures).
    expect(told, 1);
  });

  test('a calendar that takes only some new events says how many it '
      'holds', () async {
    final ledger = demoLedger();
    final port = FakeCalendars()..takesAtMost = 2;
    final sync = CalendarSync(port, directory);
    await sync.choose(
      const CalendarChoice(1, '工作', ''),
      reminderBookOf(ledger),
    );
    expect(reminderBookOf(ledger).reminders().length, greaterThan(2));
    expect(await sync.sync(reminderBookOf(ledger)), 2);
  });

  test('events leave the amounts out unless turned on, and keep that '
      'choice', () async {
    final ledger = demoLedger();
    final port = FakeCalendars();
    final sync = CalendarSync(port, directory);
    await sync.choose(
      const CalendarChoice(1, '工作', ''),
      reminderBookOf(ledger),
    );
    expect(sync.amounts, isFalse);
    await sync.sync(reminderBookOf(ledger));
    final bare = [for (final e in port.written(1)) e.title];
    for (final title in bare) {
      expect(title, isNot(contains(RegExp(r'\d'))));
    }

    await sync.setAmounts(true, reminderBookOf(ledger));
    expect(CalendarSync(port, directory).amounts, isTrue);
    final withAmounts = [for (final e in port.written(1)) e.title];
    expect(withAmounts, hasLength(bare.length));
    expect(withAmounts.any((t) => RegExp(r'\d').hasMatch(t)), isTrue);
    // The choice stays when the calendar changes.
    await sync.choose(
      const CalendarChoice(2, '家庭', 'me'),
      reminderBookOf(ledger),
    );
    expect(sync.amounts, isTrue);
  });

  test('a file of an earlier version, which wrote amounts unless told '
      'not to, now writes none', () {
    File('${directory.path}/calendar').writeAsStringSync('3\n個人');
    final sync = CalendarSync(FakeCalendars(), directory);
    expect(sync.chosen, (3, '個人'));
    expect(sync.amounts, isFalse);
  });
}
