import 'dart:async';

import 'package:core/foundation_values.dart'
    show BusinessDate, NameId, NameSalt;

import '../../../../design_system/display/amount.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/messages/reminder_messages.dart';
import 'coalesced_run.dart';
import 'reminder_rules.dart';
import 'reminders.dart';
import '../../../core/platform/preferences.dart';
import '../../../core/platform/quick_action.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../core/diagnostics/error_steps.dart';
import '../../../core/time/app_clock.dart';
import '../../../../design_system/display/status_messages.dart';

/// One notification to show at [at], on the wall clock.
final class Alert {
  const Alert(
    this.at,
    this.title,
    this.text, {
    required this.kind,
    this.quick,
    this.tag = '',
    this.confirms,
  });

  final DateTime at;
  final String title;
  final String text;

  /// Its kind: its channel, and how late it may still be posted.
  final ReminderKind kind;

  /// What tapping it opens: the composer, or the app when null.
  final QuickAction? quick;

  /// What it is about (`nudge`, `due:<key>`), so one showing can be taken
  /// away once it no longer applies.
  final String tag;

  /// The recurring item and day 「確認入帳」 on it books, through the
  /// book's inbox; null when it offers none.
  final (String, DateTime)? confirms;

  /// The same from one plan to the next, so the phone posts it once:
  /// its kind, what it is about and its day.
  String get id => '${kind.name}|$tag|${BusinessDate.of(at)}';

  /// Whether [other] says the same, at the same time.
  bool sameAs(Alert other) =>
      at == other.at &&
      title == other.title &&
      text == other.text &&
      kind == other.kind &&
      quick == other.quick &&
      tag == other.tag &&
      confirms == other.confirms;
}

/// What the phone is given to keep: every notification to come within
/// the horizon, and those just past still within their grace (posted at
/// once); whether they ring on the minute; and the tags of those that
/// still apply, so others showing are taken away.
final class ReminderPlan {
  const ReminderPlan(this.alerts, {required this.exact, required this.wanted});

  final List<Alert> alerts;
  final bool exact;
  final Set<String> wanted;

  /// Whether [other] asks the phone for the same, so it need not be told
  /// again.
  bool sameAs(ReminderPlan? other) {
    if (other == null ||
        exact != other.exact ||
        alerts.length != other.alerts.length ||
        wanted.length != other.wanted.length ||
        !wanted.containsAll(other.wanted)) {
      return false;
    }
    for (var i = 0; i < alerts.length; i++) {
      if (!alerts[i].sameAs(other.alerts[i])) return false;
    }
    return true;
  }
}

/// What the phone allows of reminders: posting them, alarms on the
/// minute, and running while the battery is saved.
typedef ReminderStatus = ({bool notifications, bool exact, bool battery});

/// The phone's notifications.
abstract interface class NotifyPort {
  /// Asks once to post notifications; whether it may.
  Future<bool> access();

  /// Hands the phone [plan] in place of the one before: it keeps it and
  /// posts each notification at its time, also after a restart, without
  /// the app.
  Future<void> schedule(ReminderPlan plan);

  /// A test notification in a minute, on the minute when [exact].
  Future<void> test({required bool exact});

  /// Posts [alert] now, as notification [id].
  Future<void> post(Alert alert, int id);

  Future<ReminderStatus> status();

  /// The system settings for alarms on the minute, and the app's own
  /// page of the system settings, where its battery use is chosen.
  Future<void> openExactSettings();
  Future<void> openBatterySettings();
}

/// The tag of the daily nudge.
const nudgeTag = 'nudge';

/// What falls due that notifications are about: from as far back as a
/// due date is still told (its grace) to the horizon.
List<Reminder> _dueReminders(ReminderBook book) => book.dueReminders();

/// The tags of notifications that still apply: what is still due, and the
/// nudge while nothing was recorded today. Others showing are taken away,
/// so recording something clears today's nudge and booking or paying an
/// item clears its notice.
Set<String> wantedTags(ReminderBook book, Preferences preferences) => {
  if (preferences.dueAlerts)
    for (final r in _dueReminders(book)) 'due:${r.key}',
  // Exception to as-of-today: an entry dated today is never 預定; anything
  // written for today will do.
  if (preferences.dailyNudge && book.entries.onDay(book.today).isEmpty)
    nudgeTag,
  // A budget's notice stays while the budget is still past its mark.
  for (final c in budgetCrossings(book, preferences)) c.tag,
};

/// The tag of the notice of the budget on [category] (a category's name,
/// a `#` and a tag, or all spending): an id that does not say it, made
/// under this install's [salt] so it cannot be matched by guessing.
String budgetTag(String category, NameSalt salt) =>
    'budget:${NameId.of(category, salt)}';

/// A budget past its warning share, or used up, this month.
typedef BudgetCrossing = ({String key, String tag, String title, String text});

/// The budgets past their warning share (or used up) this month, each as
/// the notification to post once: its key names the month, budget and
/// level, so the warning and the used up notice come once
/// each. None when budget notifications are off.
List<BudgetCrossing> budgetCrossings(
  ReminderBook book,
  Preferences preferences,
) {
  if (!preferences.budgetAlerts) return const [];
  final today = book.today;
  final month = '${today.year}-${today.month}';
  final found = <BudgetCrossing>[];
  for (final b in book.budgets.all) {
    if (b.limit <= 0) continue;
    final allowed = book.budgetService.allowance(b, today.year, today.month);
    if (allowed <= 0) continue;
    final spent = book.budgetService.spentAgainst(b, today.year, today.month);
    final share = percent(spent, allowed);
    final name = b.category == allSpending ? '本月總預算' : '「${b.category}」預算';
    // The tag Android keeps names the budget by an id, never its name.
    final tag = budgetTag(b.category, preferences.noticeSalt);
    final BudgetCrossing crossing;
    if (spent > allowed) {
      crossing = (
        key: '$month|${b.category}|over',
        tag: tag,
        title: '$name已${StatusWords.over}',
        text: '已用 ${groupDigits(spent)}，超出 ${groupDigits(spent - allowed)}',
      );
    } else if (spent * 100 >= b.warning * allowed) {
      crossing = (
        key: '$month|${b.category}|${b.warning}',
        tag: tag,
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

/// Whether [alert] goes to the phone when the plan is written at [now]:
/// still to come, or (for a kind told late) past by no more than its
/// grace, to be posted at once.
bool _stillToTell(Alert alert, DateTime now) =>
    alert.at.isAfter(now) ||
    (alert.kind.lateWhenPlanned &&
        !now.difference(alert.at).isNegative &&
        now.difference(alert.at) <= alert.kind.grace);

/// What the book has to say ahead, up to [ReminderTiming.horizonDays]: on
/// each day a recurring item or a card payment falls due (card payments
/// some days early as well), at [ReminderTiming.dueHour]; and, when asked,
/// a nudge at the chosen time on days nothing was recorded. Times after
/// [now], and due dates passed within their grace (today's 9:00 gone by,
/// a payment overdue), which the phone posts at once; soonest first.
List<Alert> alertsFor(
  ReminderBook book,
  Preferences preferences,
  DateTime now,
) {
  final alerts = <Alert>[];
  if (preferences.dueAlerts) {
    for (final r in _dueReminders(book)) {
      DateTime at(int daysBefore) => DateTime(
        r.day.year,
        r.day.month,
        r.day.day - daysBefore,
        ReminderTiming.dueHour,
      );
      final tag = 'due:${r.key}';
      alerts.add(
        Alert(
          at(0),
          r.title,
          r.note,
          kind: ReminderKind.due,
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
            at(r.daysAhead),
            '${countOf(r.daysAhead, CountUnit.days)}後 ${r.title}',
            r.note,
            kind: ReminderKind.dueAhead,
            tag: tag,
          ),
        );
      }
    }
  }
  if (preferences.dailyNudge) {
    final today = book.today;
    // Exception to as-of-today: an entry dated today is never 預定; anything
    // written for today will do.
    final recorded = book.entries.onDay(today).isNotEmpty;
    for (var d = 0; d < ReminderTiming.horizonDays; d++) {
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
          ReminderMessages.nudgeTitle,
          ReminderMessages.nudgeText,
          kind: ReminderKind.nudge,
          quick: QuickAction.expense,
          tag: nudgeTag,
        ),
      );
    }
  }
  final told = [
    for (final a in alerts)
      if (_stillToTell(a, now)) a,
  ]..sort((a, b) => a.at.compareTo(b.at));
  return told.take(ReminderTiming.most).toList();
}

/// The whole plan for the phone at [now]: [alertsFor], on the minute when
/// asked, with [wantedTags].
ReminderPlan planFor(
  ReminderBook book,
  Preferences preferences,
  DateTime now,
) => ReminderPlan(
  alertsFor(book, preferences, now),
  exact: preferences.exactReminders,
  wanted: wantedTags(book, preferences),
);

/// Keeps the phone's notifications matching the book and the person's
/// choices: planned again as soon as what they rest on changes (not a new
/// closing price), and handed to the phone only when the plan differs
/// from the one it holds.
final class Notifier {
  Notifier(this.port, this.preferences);

  final NotifyPort port;
  final Preferences preferences;

  /// The reminders chosen, the one part of the settings the plan reads: a
  /// backup noted in the background, or a theme chosen, plans nothing.
  late final _chosen = preferences.watch(const {PreferenceTopic.reminders});

  ReminderBook? _following;
  CoalescedRun? _run;

  /// The plan the phone was last given while following this book.
  ReminderPlan? _given;

  void follow(ReminderBook book) {
    stop();
    _following = book;
    _given = null;
    final run = _run = CoalescedRun(sync);
    book.addListener(run.ask);
    _chosen.addListener(run.ask);
    unawaited(sync());
  }

  void stop() {
    final run = _run;
    if (run != null) {
      run.stop();
      _following?.removeListener(run.ask);
      _chosen.removeListener(run.ask);
    }
    _run = null;
    _following = null;
  }

  /// Done once the plans asked for so far are handed over.
  Future<void> get idle => _run?.idle ?? Future<void>.value();

  /// Hands the phone what [planFor] gives now, when it differs from what
  /// it holds; and posts each budget notice not posted yet this month.
  Future<void> sync() async {
    final book = _following;
    if (book == null) return;
    try {
      final plan = planFor(book, preferences, AppClock.now());
      if (!plan.sameAs(_given)) {
        await port.schedule(plan);
        _given = plan;
      }
      await postBudgets(book);
    } on Object catch (error) {
      ErrorLog.instance.record(ErrorSteps.notifications, error);
    }
  }

  /// Posts the budget notices of [budgetCrossings] not posted before, and
  /// forgets those of earlier months.
  Future<void> postBudgets(ReminderBook book) async {
    final today = book.today;
    final month = '${today.year}-${today.month}|';
    final posted = {
      for (final key in preferences.budgetAlerted)
        if (key.startsWith(month)) key,
    };
    final fresh = [
      for (final c in budgetCrossings(book, preferences))
        if (!posted.contains(c.key)) c,
    ];
    if (fresh.isEmpty && posted.length == preferences.budgetAlerted.length) {
      return;
    }
    for (final c in fresh) {
      // Ids 700 to 763, apart from the alerts' and the test's (990).
      await port.post(
        Alert(
          AppClock.now(),
          c.title,
          c.text,
          kind: ReminderKind.budget,
          tag: c.tag,
        ),
        700 + (c.tag.hashCode & 0x3f),
      );
      posted.add(c.key);
    }
    preferences.budgetAlertedSet(posted);
  }
}
