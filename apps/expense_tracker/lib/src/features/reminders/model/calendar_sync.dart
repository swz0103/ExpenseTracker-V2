import 'dart:async';
import 'dart:io';

import '../../../core/ledger/ledger.dart';
import 'reminders.dart';
import '../../../core/perf.dart';

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

  /// Whether the events show amounts (「繳卡費：玉山卡 12,345」); off
  /// writes them without (「繳卡費：玉山卡」), for a calendar others see
  /// or that shows on the lock screen. Kept as a third line of the file.
  bool get amounts {
    if (!_file.existsSync()) return true;
    final lines = _file.readAsLinesSync();
    return lines.length < 3 || lines[2] != 'no-amounts';
  }

  /// Writes the events with or without amounts from now on, and again
  /// now for [ledger].
  Future<void> setAmounts(bool on, Ledger ledger) async {
    final calendar = chosen;
    if (calendar == null) return;
    await _write(calendar.$1, calendar.$2, amounts: on);
    await sync(ledger);
  }

  Future<void> _write(int id, String name, {required bool amounts}) => _file
      .writeAsString('$id\n$name${amounts ? '' : '\nno-amounts'}', flush: true);

  /// Syncs to [calendar] from now on; reminders still to come leave the
  /// calendar chosen before, so they are not shown twice.
  Future<void> choose(CalendarChoice calendar, Ledger ledger) async {
    final before = chosen;
    if (before != null && before.$1 != calendar.id) {
      try {
        await port.replace(before.$1, ledger.today, const []);
      } on Object catch (error) {
        Perf.instance.problem('清除舊日曆的提醒', error);
      }
    }
    await _write(calendar.id, calendar.name, amounts: amounts);
  }

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
      final reminders = ledger.reminders();
      return await port.replace(calendar.$1, ledger.today, [
        for (final r in reminders) amounts ? r : r.withoutAmount,
      ]);
    } on Object catch (error) {
      Perf.instance.problem('日曆同步', error);
      return null;
    }
  }
}
