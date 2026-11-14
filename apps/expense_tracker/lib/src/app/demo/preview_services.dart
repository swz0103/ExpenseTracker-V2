import 'dart:math';

import '../../core/connector.dart';
import '../../core/ledger/ledger.dart';
import '../../core/preferences.dart';
import '../../core/screen_privacy.dart';
import '../../features/reminders/model/notifications.dart';

/// The web preview's stand-ins for the phone: notifications that go
/// nowhere, screen hiding kept in memory and made-up daily closes, so
/// 通知與提醒, 安全, their panels and each holding's chart can be looked
/// at; nothing leaves the browser.
({Notifier notifier, ScreenPrivacy privacy, DemoPrices market}) previewServices(
  Preferences preferences, {
  Ledger Function()? ledger,
}) => (
  notifier: Notifier(const _NoNotifications(), preferences),
  privacy: ScreenPrivacy.inMemory(),
  market: DemoPrices(ledger),
);

/// Made-up daily closes for the demo's holdings: a walk of its own for
/// each code, the same each time, ending on the price the ledger holds.
final class DemoPrices extends Connector implements PriceHistory {
  DemoPrices(this._ledger) : super('收盤價');

  final Ledger Function()? _ledger;

  @override
  Future<void> refresh({bool force = false}) async {}

  @override
  Future<List<(DateTime, double)>> history(String code, DateTime from) async {
    final ledger = _ledger?.call();
    final today = ledger?.today ?? DateTime.now().toUtc();
    final end = ledger?.holding(code)?.price ?? 100;
    final days = <DateTime>[
      for (
        var d = DateTime.utc(from.year, from.month, from.day);
        !d.isAfter(today);
        d = d.add(const Duration(days: 1))
      )
        if (d.weekday <= DateTime.friday) d,
    ];
    if (days.isEmpty) return const [];
    // Walked from a fixed start back to front, rising on the whole.
    final random = Random(code.codeUnits.fold<int>(7, (a, b) => a * 31 + b));
    final walk = <double>[1];
    for (var i = 1; i < days.length; i++) {
      walk.add(walk.last * (1 + (random.nextDouble() - 0.47) * 0.024));
    }
    final scale = end / walk.last;
    return [
      for (final (i, day) in days.indexed)
        (day, double.parse((walk[i] * scale).toStringAsFixed(2))),
    ];
  }
}

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
