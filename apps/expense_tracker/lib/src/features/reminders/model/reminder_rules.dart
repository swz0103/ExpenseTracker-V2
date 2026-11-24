import '../../../core/messages/reminder_messages.dart';

/// The phone's notification channels: one for each kind the person may
/// want to silence on its own, such as the daily nudge while keeping the
/// due dates. [name] is the id the phone keeps; the words are what its
/// settings show.
enum ReminderChannel {
  due(ReminderMessages.dueChannel, ReminderMessages.dueChannelAbout),
  nudge(ReminderMessages.nudgeChannel, ReminderMessages.nudgeChannelAbout),
  budget(ReminderMessages.budgetChannel, ReminderMessages.budgetChannelAbout);

  const ReminderChannel(this.title, this.about);

  final String title;
  final String about;

  /// Channels of earlier versions, taken away from the phone's settings:
  /// the one channel every reminder shared.
  static const retired = ['reminders'];
}

/// The kinds of notification, each with its channel and its grace window:
/// how long after its time a notification the phone could not post then
/// (it was off, or the alarm was lost) is still worth posting. Past that
/// it is dropped. With [lateWhenPlanned], one whose time has passed when
/// the plan is written is posted at once as well (within its grace): a
/// payment due today, or already overdue, is told even though its 9:00
/// went by before it was known.
enum ReminderKind {
  /// On the day a recurring item or a card payment falls due.
  due(ReminderChannel.due, grace: Duration(days: 7), lateWhenPlanned: true),

  /// Some days before a card payment.
  dueAhead(ReminderChannel.due, grace: Duration(hours: 12)),

  /// On days nothing was recorded, at the chosen time.
  nudge(ReminderChannel.nudge, grace: Duration(hours: 3)),

  /// A budget past its warning share, posted when it is seen.
  budget(ReminderChannel.budget, grace: Duration.zero),

  /// 試一則.
  test(ReminderChannel.due, grace: Duration.zero);

  const ReminderKind(
    this.channel, {
    required this.grace,
    this.lateWhenPlanned = false,
  });

  final ReminderChannel channel;
  final Duration grace;
  final bool lateWhenPlanned;
}

/// The times of the reminders: how far ahead the phone is told, at what
/// hour a due date is told, and what the phone allows.
abstract final class ReminderTiming {
  /// How many days ahead the phone is given its notifications. The phone
  /// keeps them and posts them without the app, so a person who does not
  /// open the app for weeks is still reminded; the plan is written again
  /// each time the app is opened or what it rests on changes.
  static const horizonDays = 62;

  /// The most notifications the phone is asked to keep at once, soonest
  /// first. One on the minute takes two alarms (the exact one and its
  /// inexact twin, ReminderAlarms.kt): 320, well under the 500 alarms
  /// Android allows an app.
  static const most = 160;

  /// The hour a due date is told on its day (and days before), and the
  /// hour of its event in the calendar.
  static const dueHour = 9;

  /// How many days before a card payment it is told as well.
  static const cardWarnDays = 2;

  /// How late Android may post a reminder when alarms on the minute are
  /// off or not allowed: its window for inexact alarms, as measured on a
  /// phone (an alarm set for 00:21 came at 00:26; the window is an hour).
  static const inexactLateness = Duration(hours: 1);
}
