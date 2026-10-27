import 'dart:async';

import '../../../core/ledger/ledger.dart';
import 'reminders.dart';
import '../../../core/perf.dart';
import '../../../core/preferences.dart';
import '../../../core/quick_action.dart';

/// One notification to show at [at].
final class Alert {
  const Alert(this.at, this.title, this.text, {this.quick, this.tag = ''});

  final DateTime at;
  final String title;
  final String text;

  /// What tapping it opens: the composer, or the app when null.
  final QuickAction? quick;

  /// What it is about (`nudge`, `due:<key>`), so one showing can be taken
  /// away once it no longer applies.
  final String tag;
}

/// What the phone allows of reminders: posting them, alarms on the
/// minute, and running while the battery is saved.
typedef ReminderStatus = ({bool notifications, bool exact, bool battery});

/// The phone's notifications.
abstract interface class NotifyPort {
  /// Asks once to post notifications; whether it may.
  Future<bool> access();

  /// Replaces every notification still to come with [alerts], on the
  /// minute when [exact]; those showing whose tag is not [wanted] are
  /// taken away.
  Future<void> schedule(
    List<Alert> alerts, {
    bool exact = false,
    Set<String>? wanted,
  });

  /// A test notification in a minute.
  Future<void> test({bool exact = false});

  Future<ReminderStatus> status();

  /// The system settings for alarms on the minute, and for the battery.
  Future<void> openExactSettings();
  Future<void> openBatterySettings();
}

/// The tag of the daily nudge.
const nudgeTag = 'nudge';

/// The tags of notifications that still apply: what is still due, and the
/// nudge while nothing was recorded today. Others showing are taken away,
/// so recording something clears today's nudge and booking or paying an
/// item clears its notice.
Set<String> wantedTags(Ledger ledger, Preferences preferences) => {
  if (preferences.dueAlerts)
    for (final r in ledger.reminders(days: 30)) 'due:${r.key}',
  if (preferences.dailyNudge && ledger.entriesOn(ledger.today).isEmpty)
    nudgeTag,
};

/// The most notifications kept waiting at once.
const _most = 48;

/// What the ledger has to say ahead: on each day a recurring item or a
/// card payment falls due (card payments two days early as well), at
/// 9:00; and, when asked, a nudge at the chosen time on days nothing was
/// recorded. Only times after [now], soonest first.
List<Alert> alertsFor(Ledger ledger, Preferences preferences, DateTime now) {
  final alerts = <Alert>[];
  if (preferences.dueAlerts) {
    for (final r in ledger.reminders(days: 30)) {
      DateTime nine(int daysBefore) =>
          DateTime(r.day.year, r.day.month, r.day.day - daysBefore, 9);
      final tag = 'due:${r.key}';
      alerts.add(Alert(nine(0), r.title, r.note, tag: tag));
      if (r.daysAhead > 0) {
        alerts.add(
          Alert(
            nine(r.daysAhead),
            '${r.daysAhead} 天後 ${r.title}',
            r.note,
            tag: tag,
          ),
        );
      }
    }
  }
  if (preferences.dailyNudge) {
    final today = ledger.today;
    final recorded = ledger.entriesOn(today).isNotEmpty;
    for (var d = 0; d < 7; d++) {
      if (d == 0 && recorded) continue;
      final at = DateTime(
        today.year,
        today.month,
        today.day + d,
        preferences.nudgeHour,
        preferences.nudgeMinute,
      );
      alerts.add(
        Alert(
          at,
          '今天記帳了嗎？',
          '點一下記一筆',
          quick: QuickAction.expense,
          tag: nudgeTag,
        ),
      );
    }
  }
  final ahead = [
    for (final a in alerts)
      if (a.at.isAfter(now)) a,
  ]..sort((a, b) => a.at.compareTo(b.at));
  return ahead.take(_most).toList();
}

/// Keeps the phone's notifications matching the ledger and the person's
/// choices: rescheduled a few seconds after either changes.
final class Notifier {
  Notifier(this.port, this.preferences);

  final NotifyPort port;
  final Preferences preferences;

  Ledger? _following;
  Timer? _timer;

  void follow(Ledger ledger) {
    stop();
    _following = ledger;
    ledger.addListener(_changed);
    preferences.addListener(_changed);
    unawaited(sync());
  }

  void stop() {
    _timer?.cancel();
    _following?.removeListener(_changed);
    preferences.removeListener(_changed);
    _following = null;
  }

  void _changed() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () => unawaited(sync()));
  }

  /// Schedules what [alertsFor] gives now; none when nothing is asked for.
  Future<void> sync() async {
    final ledger = _following;
    if (ledger == null) return;
    try {
      await port.schedule(
        alertsFor(ledger, preferences, DateTime.now()),
        exact: preferences.exactReminders,
        wanted: wantedTags(ledger, preferences),
      );
    } on Object catch (error) {
      Perf.instance.problem('通知', error);
    }
  }
}
