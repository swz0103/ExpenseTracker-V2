import 'package:core/foundation_values.dart' show BusinessDate;

import '../../core/messages/reminder_messages.dart';
import '../../features/reminders/model/reminder_alerts.dart';
import '../../features/reminders/model/reminder_rules.dart';
import 'platform_channel.dart';

/// Notifications through `Reminders.kt`, which only keeps and posts what
/// it is given: each alert of the plan goes with its time on the wall
/// clock (so the phone can work its alarm out again when the time zone or
/// the clock changes), its grace window, its channel and its words; the
/// channels go with their names. What is due, how late it may come and
/// what it says are all decided here, in Dart.
final class AndroidNotifications implements NotifyPort {
  const AndroidNotifications();

  /// The channels, as the phone keeps them; those of earlier versions
  /// ([ReminderChannel.retired]) are taken away with each plan.
  static List<Map<String, String>> get channels => [
    for (final c in ReminderChannel.values)
      {'id': c.name, 'name': c.title, 'about': c.about},
  ];

  /// [alert] as the phone keeps it.
  static Map<String, Object?> alertFields(Alert alert) {
    final local = alert.at.toLocal();
    return {
      'id': alert.id,
      'at': alert.at.millisecondsSinceEpoch,
      'y': local.year,
      'm': local.month,
      'd': local.day,
      'hour': local.hour,
      'minute': local.minute,
      'grace': alert.kind.grace.inMilliseconds,
      'channel': alert.kind.channel.name,
      'title': alert.title,
      'text': alert.text,
      'quick': alert.quick?.name ?? '',
      'tag': alert.tag,
      if (alert.confirms case (final id, final day)) ...{
        'recurring': id,
        'day': BusinessDate.of(day).toString(),
      },
    };
  }

  @override
  Future<bool> access() async =>
      await platformChannel.invokeMethod<bool>('notificationAccess') ?? false;

  @override
  Future<void> schedule(ReminderPlan plan) =>
      platformChannel.invokeMethod<void>('scheduleNotifications', {
        'exact': plan.exact,
        'wanted': plan.wanted.toList(),
        'channels': channels,
        'retired': ReminderChannel.retired,
        'alerts': [for (final a in plan.alerts) alertFields(a)],
      });

  @override
  Future<void> test({required bool exact}) =>
      platformChannel.invokeMethod<void>('testNotification', {
        'exact': exact,
        'channels': channels,
        'channel': ReminderKind.test.channel.name,
        'title': ReminderMessages.testTitle,
        'text': ReminderMessages.testText,
      });

  @override
  Future<void> post(Alert alert, int id) =>
      platformChannel.invokeMethod<void>('showNotification', {
        'id': id,
        'channels': channels,
        'channel': alert.kind.channel.name,
        'title': alert.title,
        'text': alert.text,
        'tag': alert.tag,
        'quick': alert.quick?.name ?? '',
      });

  @override
  Future<ReminderStatus> status() async {
    final found =
        await platformChannel.invokeMapMethod<String, Object?>(
          'reminderStatus',
        ) ??
        const {};
    return (
      notifications: found['notifications'] == true,
      exact: found['exact'] == true,
      battery: found['battery'] == true,
    );
  }

  @override
  Future<void> openExactSettings() =>
      platformChannel.invokeMethod<void>('openExactSettings');

  @override
  Future<void> openBatterySettings() =>
      platformChannel.invokeMethod<void>('openBatterySettings');
}
