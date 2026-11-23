import 'dart:io';

import 'package:expense_tracker/src/features/reminders/model/calendar_sync.dart';

/// A calendar app in memory: the app's events each calendar holds, with
/// ids as the calendar gives them, and what each change did.
final class FakeCalendars implements CalendarPort {
  FakeCalendars({
    this.choices = const [
      CalendarChoice(1, '工作', ''),
      CalendarChoice(2, '家庭', 'me@example.com'),
    ],
  });

  List<CalendarChoice> choices;
  var allows = true;
  var listFails = false;
  var writeFails = false;

  /// Calendar access taken away in the system settings since: reading or
  /// writing events is refused.
  var revoked = false;

  /// Out of reach, as a provider that is gone.
  var reachable = true;

  /// At most this many new events written at once, the rest left out.
  int? takesAtMost;

  final _held = <int, List<CalendarEvent>>{};
  var _nextId = 100;

  /// Every change made, in order.
  final applied = <(int, CalendarChanges)>[];

  /// The events [calendar] holds, soonest first.
  List<CalendarEvent> written(int calendar) =>
      [...?_held[calendar]]..sort((a, b) => a.start.compareTo(b.start));

  @override
  Future<bool> access() async => allows;

  @override
  Future<List<CalendarChoice>> calendars() async {
    if (listFails) throw const SocketException('calendar provider gone');
    return choices;
  }

  void _check() {
    if (revoked) throw StateError('no-access');
    if (!reachable) throw const SocketException('offline');
  }

  @override
  Future<List<CalendarEvent>> events(int calendar, DateTime from) async {
    _check();
    final start = DateTime(from.year, from.month, from.day);
    return [
      for (final e in _held[calendar] ?? const <CalendarEvent>[])
        if (!e.start.isBefore(start)) e,
    ];
  }

  @override
  Future<int> apply(int calendar, CalendarChanges changes) async {
    _check();
    if (writeFails) throw StateError('read only');
    applied.add((calendar, changes));
    final held = _held[calendar] ??= [];
    held.removeWhere((e) => changes.delete.contains(e.id));
    for (final u in changes.update) {
      final at = held.indexWhere((e) => e.id == u.id);
      held[at] = u;
    }
    final fits = changes.insert.take(takesAtMost ?? changes.insert.length);
    for (final e in fits) {
      held.add(e.replacing(_nextId++));
    }
    return fits.length;
  }
}
