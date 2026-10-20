import 'dart:async';

import 'model/ledger.dart';
import 'model/reminders.dart';
import 'perf.dart';
import 'preferences.dart';

/// One notification to show at [at].
final class Alert {
  const Alert(this.at, this.title, this.text, {this.quick});

  final DateTime at;
  final String title;
  final String text;

  /// What tapping it opens: `expense` opens the composer; null the app.
  final String? quick;
}

/// The phone's notifications.
abstract interface class NotifyPort {
  /// Asks once to post notifications; whether it may.
  Future<bool> access();

  /// Replaces every notification still to come with [alerts].
  Future<void> schedule(List<Alert> alerts);
}

/// The most notifications kept waiting at once.
const _most = 48;

/// What the ledger has to say ahead: on each day a recurring item or a
/// card payment falls due (card payments two days early as well), at
/// 9:00; and, when asked, a nudge at the chosen hour on days nothing was
/// recorded. Only times after [now], soonest first.
List<Alert> alertsFor(Ledger ledger, Preferences preferences, DateTime now) {
  final alerts = <Alert>[];
  if (preferences.dueAlerts) {
    for (final r in ledger.reminders(days: 30)) {
      DateTime nine(int daysBefore) =>
          DateTime(r.day.year, r.day.month, r.day.day - daysBefore, 9);
      alerts.add(Alert(nine(0), r.title, r.note));
      if (r.daysAhead > 0) {
        alerts.add(
          Alert(nine(r.daysAhead), '${r.daysAhead} 天後 ${r.title}', r.note),
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
      );
      alerts.add(Alert(at, '今天記帳了嗎？', '點一下記一筆', quick: 'expense'));
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
      await port.schedule(alertsFor(ledger, preferences, DateTime.now()));
    } on Object catch (error) {
      Perf.instance.problem('通知', error);
    }
  }
}
