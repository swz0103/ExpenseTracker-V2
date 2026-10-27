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
  Future<void> schedule(List<Alert> alerts) =>
      platformChannel.invokeMethod<void>('scheduleNotifications', {
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
            },
        ],
      });
}
