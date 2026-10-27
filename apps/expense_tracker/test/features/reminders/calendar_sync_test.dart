import 'dart:io';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/features/reminders/model/calendar_sync.dart';
import 'package:expense_tracker/src/features/reminders/model/reminders.dart';
import 'package:flutter_test/flutter_test.dart';

/// A calendar app in memory: what each calendar holds from a day on.
final class _Calendars implements CalendarPort {
  final held = <int, List<Reminder>>{};
  var reachable = true;

  @override
  Future<bool> access() async => true;

  @override
  Future<List<CalendarChoice>> calendars() async => const [
    CalendarChoice(1, '個人', 'me@example.com'),
    CalendarChoice(2, '家庭', 'me@example.com'),
  ];

  @override
  Future<int> replace(
    int calendar,
    DateTime from,
    List<Reminder> reminders,
  ) async {
    if (!reachable) throw const SocketException('offline');
    held[calendar] = reminders;
    return reminders.length;
  }
}

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('calendar-'));
  tearDown(() => directory.deleteSync(recursive: true));

  test('what falls due goes to the chosen calendar only', () async {
    final ledger = demoLedger();
    final port = _Calendars();
    final sync = CalendarSync(port, directory);
    expect(await sync.sync(ledger), isNull);

    await sync.choose(const CalendarChoice(1, '個人', 'me'), ledger);
    expect(sync.chosen, (1, '個人'));
    final written = await sync.sync(ledger);
    expect(written, ledger.reminders().length);
    expect(written, greaterThan(0));

    // Moving to another calendar takes them off the first.
    await sync.choose(const CalendarChoice(2, '家庭', 'me'), ledger);
    expect(port.held[1], isEmpty);
    await sync.sync(ledger);
    expect(port.held[2], isNotEmpty);

    // Chosen again after a restart of the app.
    expect(CalendarSync(port, directory).chosen, (2, '家庭'));

    await sync.forget(ledger);
    expect(port.held[2], isEmpty);
    expect(sync.chosen, isNull);
  });

  test('a calendar out of reach is noted, not thrown', () async {
    final ledger = demoLedger();
    final port = _Calendars();
    final sync = CalendarSync(port, directory);
    await sync.choose(const CalendarChoice(1, '個人', 'me'), ledger);
    port.reachable = false;
    expect(await sync.sync(ledger), isNull);
  });
}
