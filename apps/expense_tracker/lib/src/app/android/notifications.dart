import '../../features/reminders/model/notifications.dart';
import 'channel.dart';

/// Notifications through `Reminders.kt`: each alert is an alarm that
/// posts it, kept across restarts of the phone. Each goes with its time on
/// the wall clock as well as its instant, so the phone can work the alarm
/// out again when the time zone or the clock changes.
final class AndroidNotifications implements NotifyPort {
  const AndroidNotifications();

  @override
  Future<bool> access() async =>
      await platformChannel.invokeMethod<bool>('notificationAccess') ?? false;

  @override
  Future<void> schedule(
    List<Alert> alerts, {
    bool exact = false,
    Set<String>? wanted,
  }) => platformChannel.invokeMethod<void>('scheduleNotifications', {
    'exact': exact,
    'wanted': ?wanted?.toList(),
    'alerts': [
      for (final a in alerts)
        {
          'at': a.at.millisecondsSinceEpoch,
          'y': a.at.toLocal().year,
          'm': a.at.toLocal().month,
          'd': a.at.toLocal().day,
          'hour': a.at.toLocal().hour,
          'minute': a.at.toLocal().minute,
          'title': a.title,
          'text': a.text,
          'quick': a.quick?.name,
          'tag': a.tag,
          if (a.confirms case (final id, final day)) ...{
            'recurring': id,
            'day':
                '${day.year}-${day.month.toString().padLeft(2, '0')}'
                '-${day.day.toString().padLeft(2, '0')}',
          },
        },
    ],
  });

  @override
  Future<void> test({bool exact = false}) =>
      platformChannel.invokeMethod<void>('testNotification', {'exact': exact});

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
