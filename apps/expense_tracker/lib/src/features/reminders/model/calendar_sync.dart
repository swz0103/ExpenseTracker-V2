import 'dart:async';
import 'dart:io';

import 'coalesced_run.dart';
import 'reminder_rules.dart';
import 'reminders.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../core/diagnostics/error_steps.dart';

/// A calendar on the phone, such as one synced with Google Calendar.
final class CalendarChoice {
  const CalendarChoice(this.id, this.name, this.account);

  final int id;
  final String name;

  /// The account it syncs with, such as a Gmail address.
  final String account;
}

/// An event the app keeps in a calendar: what falls due on a day, at
/// [start], reminding [remind] minutes before (0 for at its time).
final class CalendarEvent {
  const CalendarEvent({
    required this.key,
    required this.title,
    required this.note,
    required this.start,
    required this.remind,
    this.id,
  });

  /// [reminder] as its event, with its amount when [amounts]: at
  /// [ReminderTiming.dueHour] on its day, reminding then and its days
  /// ahead before.
  factory CalendarEvent.of(Reminder reminder, {required bool amounts}) {
    final r = amounts ? reminder : reminder.withoutAmount;
    return CalendarEvent(
      key: r.key,
      title: r.title,
      note: r.note,
      start: DateTime(
        r.day.year,
        r.day.month,
        r.day.day,
        ReminderTiming.dueHour,
      ),
      remind: [
        0,
        if (r.daysAhead > 0) Duration(days: r.daysAhead).inMinutes,
      ],
    );
  }

  /// The calendar's own id of an event read back from it; null for one
  /// still to write.
  final int? id;

  /// The reminder it is of ([Reminder.key]): the same from one sync to the
  /// next, so an event is changed in place rather than written again.
  final String key;
  final String title;
  final String note;
  final DateTime start;
  final List<int> remind;

  /// Whether [other] says the same, at the same time, reminding the same.
  bool sameAs(CalendarEvent other) =>
      key == other.key &&
      title == other.title &&
      note == other.note &&
      start == other.start &&
      remind.length == other.remind.length &&
      remind.toSet().containsAll(other.remind);

  /// This event in place of the calendar's event [id].
  CalendarEvent replacing(int id) => CalendarEvent(
    key: key,
    title: title,
    note: note,
    start: start,
    remind: remind,
    id: id,
  );
}

/// What a sync changes in a calendar: events to write, events to change
/// in place (by their [CalendarEvent.id]) and the ids of events to take
/// away.
final class CalendarChanges {
  const CalendarChanges({
    this.insert = const [],
    this.update = const [],
    this.delete = const [],
  });

  final List<CalendarEvent> insert;
  final List<CalendarEvent> update;
  final List<int> delete;

  bool get isEmpty => insert.isEmpty && update.isEmpty && delete.isEmpty;
}

/// What turns the app's events [held] in a calendar into [wanted], by
/// key: one the same is left alone, one changed is changed in place,
/// one no longer wanted (or held twice) is taken away, one new is
/// written. New ones keep the order of [wanted] (soonest first), so when
/// the calendar takes only so many at once the nearest go first.
CalendarChanges calendarChanges(
  List<CalendarEvent> held,
  List<CalendarEvent> wanted,
) {
  final byKey = <String, List<CalendarEvent>>{};
  for (final e in held) {
    (byKey[e.key] ??= []).add(e);
  }
  final insert = <CalendarEvent>[];
  final update = <CalendarEvent>[];
  final delete = <int>[];
  for (final w in wanted) {
    final same = byKey.remove(w.key);
    if (same == null || same.isEmpty) {
      insert.add(w);
      continue;
    }
    final keep = same.first;
    if (!keep.sameAs(w)) update.add(w.replacing(keep.id!));
    for (final extra in same.skip(1)) {
      delete.add(extra.id!);
    }
  }
  for (final gone in byKey.values) {
    for (final e in gone) {
      delete.add(e.id!);
    }
  }
  return CalendarChanges(insert: insert, update: update, delete: delete);
}

/// Where reminders are written: the phone's calendars, on Android.
abstract interface class CalendarPort {
  /// Asks for the calendar once; whether it may be used.
  Future<bool> access();

  Future<List<CalendarChoice>> calendars();

  /// The app's events in [calendar] from the start of [from] on.
  Future<List<CalendarEvent>> events(int calendar, DateTime from);

  /// Makes [changes] in [calendar], all or none, and asks the calendar
  /// to sync them soon; how many of [CalendarChanges.insert] were
  /// written (the nearest, when there are more than fit at once).
  Future<int> apply(int calendar, CalendarChanges changes);
}

/// Keeps the chosen calendar holding what the book has falling due, so
/// the calendar's own reminders say when to pay. The choice belongs to
/// this phone and is kept beside the book, with whether the events show
/// amounts: they do not unless the person turns that on, as a calendar
/// is often shared or shown on the lock screen.
final class CalendarSync {
  CalendarSync(this.port, this.directory, {this.failed});

  /// Told when a sync fails, so the person hears of it (D84).
  final void Function()? failed;

  final CalendarPort port;
  final Directory directory;

  File get _file => File('${directory.path}/calendar');

  /// The third line of the file when the events show amounts.
  static const _amountsOn = 'amounts';

  /// The chosen calendar's id and name; null until one is chosen.
  (int, String)? get chosen {
    if (!_file.existsSync()) return null;
    final lines = _file.readAsLinesSync();
    final id = lines.isEmpty ? null : int.tryParse(lines.first);
    if (id == null) return null;
    return (id, lines.length > 1 ? lines[1] : '');
  }

  /// Whether the events show amounts (「繳卡費：玉山卡 12,345」); off,
  /// as it is unless turned on, writes them without (「繳卡費：玉山卡」).
  /// Kept as a third line of the file.
  bool get amounts {
    if (!_file.existsSync()) return false;
    final lines = _file.readAsLinesSync();
    return lines.length > 2 && lines[2] == _amountsOn;
  }

  /// Writes the events with or without amounts from now on, and changes
  /// those in [book]'s calendar now.
  Future<void> setAmounts(bool on, ReminderBook book) async {
    final calendar = chosen;
    if (calendar == null) return;
    await _write(calendar.$1, calendar.$2, amounts: on);
    await sync(book);
  }

  Future<void> _write(int id, String name, {required bool amounts}) =>
      _file.writeAsString(
        '$id\n$name${amounts ? '\n$_amountsOn' : ''}',
        flush: true,
      );

  /// Takes the app's events from [from] on off [calendar].
  Future<void> _clear(int calendar, DateTime from) async {
    final held = await port.events(calendar, from);
    if (held.isEmpty) return;
    await port.apply(calendar, calendarChanges(held, const []));
  }

  /// Syncs to [calendar] from now on; reminders still to come leave the
  /// calendar chosen before, so they are not shown twice.
  Future<void> choose(CalendarChoice calendar, ReminderBook book) async {
    final before = chosen;
    if (before != null && before.$1 != calendar.id) {
      try {
        await _clear(before.$1, book.today);
      } on Object catch (error) {
        ErrorLog.instance.record(ErrorSteps.calendarClear, error);
      }
    }
    await _write(calendar.id, calendar.name, amounts: amounts);
  }

  /// Stops syncing and takes the reminders still to come off the
  /// calendar; whether they could be. The link is dropped either way, as
  /// when calendar access was turned off since.
  Future<bool> forget(ReminderBook book) async {
    final calendar = chosen;
    if (calendar == null) return true;
    try {
      await _clear(calendar.$1, book.today);
      return true;
    } on Object catch (error) {
      ErrorLog.instance.record(ErrorSteps.calendarClear, error);
      return false;
    } finally {
      if (_file.existsSync()) await _file.delete();
    }
  }

  CoalescedRun? _run;
  ReminderBook? _following;

  /// Syncs [book] now, then as soon as what falls due may have changed.
  void follow(ReminderBook book) {
    stop();
    _following = book;
    final run = _run = CoalescedRun(() async => sync(book));
    book.addListener(run.ask);
    unawaited(sync(book));
  }

  void stop() {
    final run = _run;
    if (run != null) {
      run.stop();
      _following?.removeListener(run.ask);
    }
    _run = null;
    _following = null;
  }

  /// Done once the syncs asked for so far are done.
  Future<void> get idle => _run?.idle ?? Future<void>.value();

  /// Brings the chosen calendar to what falls due, changing only the
  /// events that differ; how many events it holds of them. Null when none
  /// is chosen or the calendar cannot be reached.
  Future<int?> sync(ReminderBook book) async {
    final calendar = chosen;
    if (calendar == null) return null;
    try {
      final wanted = [
        for (final r in book.dueReminders())
          CalendarEvent.of(r, amounts: amounts),
      ];
      // The same window as the notifications (D68): an overdue day still
      // unbooked stays on the calendar, and leaves it once booked.
      final held = await port.events(calendar.$1, book.windowStart);
      final changes = calendarChanges(held, wanted);
      if (changes.isEmpty) return wanted.length;
      final inserted = await port.apply(calendar.$1, changes);
      return wanted.length - (changes.insert.length - inserted);
    } on Object catch (error) {
      ErrorLog.instance.record(ErrorSteps.calendarSync, error);
      failed?.call();
      return null;
    }
  }
}
