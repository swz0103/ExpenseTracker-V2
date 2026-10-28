import 'dart:async';

import '../../../core/ledger/amounts.dart';
import '../../../core/ledger/ledger.dart';
import 'reminders.dart';
import '../../../core/perf.dart';
import '../../../core/preferences.dart';
import '../../../core/quick_action.dart';

/// One notification to show at [at].
final class Alert {
  const Alert(
    this.at,
    this.title,
    this.text, {
    this.quick,
    this.tag = '',
    this.confirms,
  });

  final DateTime at;
  final String title;
  final String text;

  /// What tapping it opens: the composer, or the app when null.
  final QuickAction? quick;

  /// What it is about (`nudge`, `due:<key>`), so one showing can be taken
  /// away once it no longer applies.
  final String tag;

  /// The recurring item and day 「確認入帳」 on it books, through the
  /// ledger's inbox; null when it offers none.
  final (String, DateTime)? confirms;
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

  /// Posts [alert] now, as notification [id].
  Future<void> post(Alert alert, int id);

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
  // A budget's notice stays while the budget is still past its mark.
  for (final c in budgetCrossings(ledger, preferences)) c.tag,
};

/// A budget past its warning share, or used up, this month.
typedef BudgetCrossing = ({String key, String tag, String title, String text});

/// The budgets past their warning share (or used up) this month, each as
/// the notification to post once: its key names the month, budget and
/// level, so the warning and the used up notice come once
/// each. None when budget notifications are off.
List<BudgetCrossing> budgetCrossings(Ledger ledger, Preferences preferences) {
  if (!preferences.budgetAlerts) return const [];
  final today = ledger.today;
  final month = '${today.year}-${today.month}';
  final found = <BudgetCrossing>[];
  for (final b in ledger.budgets) {
    if (b.limit <= 0) continue;
    final allowed = ledger.allowance(b, today.year, today.month);
    if (allowed <= 0) continue;
    final spent = ledger.spentAgainst(b, today.year, today.month);
    final share = spent * 100 ~/ allowed;
    final name = b.category == Ledger.allSpending
        ? '本月總預算'
        : '「${b.category}」預算';
    final BudgetCrossing crossing;
    if (spent > allowed) {
      crossing = (
        key: '$month|${b.category}|over',
        tag: 'budget:${b.category}',
        title: '$name已超支',
        text: '已用 ${groupDigits(spent)}，超出 ${groupDigits(spent - allowed)}',
      );
    } else if (share >= b.warning) {
      crossing = (
        key: '$month|${b.category}|${b.warning}',
        tag: 'budget:${b.category}',
        title: '$name已用 $share%',
        text: '還剩 ${groupDigits(allowed - spent)}',
      );
    } else {
      continue;
    }
    found.add(crossing);
  }
  return found;
}

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
      alerts.add(
        Alert(
          nine(0),
          r.title,
          r.note,
          tag: tag,
          confirms: switch (r.recurring) {
            final id? => (id, r.day),
            null => null,
          },
        ),
      );
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

  /// Schedules what [alertsFor] gives now, none when nothing is asked
  /// for; and posts each budget notice not posted yet this month.
  Future<void> sync() async {
    final ledger = _following;
    if (ledger == null) return;
    try {
      await port.schedule(
        alertsFor(ledger, preferences, DateTime.now()),
        exact: preferences.exactReminders,
        wanted: wantedTags(ledger, preferences),
      );
      await postBudgets(ledger);
    } on Object catch (error) {
      Perf.instance.problem('通知', error);
    }
  }

  /// Posts the budget notices of [budgetCrossings] not posted before, and
  /// forgets those of earlier months.
  Future<void> postBudgets(Ledger ledger) async {
    final today = ledger.today;
    final month = '${today.year}-${today.month}|';
    final posted = {
      for (final key in preferences.budgetAlerted)
        if (key.startsWith(month)) key,
    };
    final fresh = [
      for (final c in budgetCrossings(ledger, preferences))
        if (!posted.contains(c.key)) c,
    ];
    if (fresh.isEmpty && posted.length == preferences.budgetAlerted.length) {
      return;
    }
    for (final c in fresh) {
      // Ids 700 to 763, apart from the alerts' and the test's (990).
      await port.post(
        Alert(DateTime.now(), c.title, c.text, tag: c.tag),
        700 + (c.tag.hashCode & 0x3f),
      );
      posted.add(c.key);
    }
    preferences.budgetAlertedSet(posted);
  }
}
