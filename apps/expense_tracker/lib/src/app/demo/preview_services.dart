import '../../core/preferences.dart';
import '../../core/screen_privacy.dart';
import '../../features/reminders/model/notifications.dart';

/// The web preview's stand-ins for the phone: notifications that go
/// nowhere and screen hiding kept in memory, so 通知與提醒, 安全 and their
/// panels can be looked at; nothing leaves the browser.
({Notifier notifier, ScreenPrivacy privacy}) previewServices(
  Preferences preferences,
) => (
  notifier: Notifier(const _NoNotifications(), preferences),
  privacy: ScreenPrivacy.inMemory(),
);

final class _NoNotifications implements NotifyPort {
  const _NoNotifications();

  @override
  Future<bool> access() async => true;

  @override
  Future<void> schedule(
    List<Alert> alerts, {
    bool exact = false,
    Set<String>? wanted,
  }) async {}

  @override
  Future<void> test({bool exact = false}) async {}

  @override
  Future<void> post(Alert alert, int id) async {}

  @override
  Future<ReminderStatus> status() async =>
      (notifications: true, exact: true, battery: true);

  @override
  Future<void> openExactSettings() async {}

  @override
  Future<void> openBatterySettings() async {}
}
