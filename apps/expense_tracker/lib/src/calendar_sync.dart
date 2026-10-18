import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import 'model/ledger.dart';
import 'model/reminders.dart';

/// A calendar on the phone, such as one synced with Google Calendar.
final class CalendarChoice {
  const CalendarChoice(this.id, this.name, this.account);

  final int id;
  final String name;

  /// The account it syncs with, such as a Gmail address.
  final String account;
}

/// Where reminders are written: the phone's calendars, on Android.
abstract interface class CalendarPort {
  /// Asks for the calendar once; whether it may be used.
  Future<bool> access();

  Future<List<CalendarChoice>> calendars();

  /// Replaces the app's events from [from] on in [calendar] with
  /// [reminders]; returns how many were written.
  Future<int> replace(int calendar, DateTime from, List<Reminder> reminders);
}

/// Keeps the chosen calendar holding what the ledger has falling due, so
/// the calendar's own reminders say when to pay. The choice belongs to
/// this phone and is kept beside the ledger.
final class CalendarSync {
  CalendarSync(this.port, this.directory);

  final CalendarPort port;
  final Directory directory;

  File get _file => File('${directory.path}/calendar');

  /// The chosen calendar's id and name; null until one is chosen.
  (int, String)? get chosen {
    if (!_file.existsSync()) return null;
    final lines = _file.readAsLinesSync();
    final id = lines.isEmpty ? null : int.tryParse(lines.first);
    if (id == null) return null;
    return (id, lines.length > 1 ? lines[1] : '');
  }

  Future<void> choose(CalendarChoice calendar) =>
      _file.writeAsString('${calendar.id}\n${calendar.name}', flush: true);

  /// Stops syncing and takes the reminders still to come off the calendar.
  Future<void> forget(Ledger ledger) async {
    final calendar = chosen;
    if (calendar == null) return;
    await port.replace(calendar.$1, ledger.today, const []);
    await _file.delete();
  }

  Timer? _timer;
  Ledger? _following;

  /// Syncs [ledger] now, then a few seconds after it last changed.
  void follow(Ledger ledger) {
    stop();
    _following = ledger;
    ledger.addListener(_changed);
    unawaited(sync(ledger));
  }

  void stop() {
    _timer?.cancel();
    _following?.removeListener(_changed);
    _following = null;
  }

  void _changed() {
    final ledger = _following;
    if (ledger == null) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), () => unawaited(sync(ledger)));
  }

  /// Writes what falls due into the chosen calendar; null when none is
  /// chosen or the calendar cannot be reached.
  Future<int?> sync(Ledger ledger) async {
    final calendar = chosen;
    if (calendar == null) return null;
    try {
      return await port.replace(calendar.$1, ledger.today, ledger.reminders());
    } on Object catch (error) {
      debugPrint('Calendar not synced: $error');
      return null;
    }
  }
}
