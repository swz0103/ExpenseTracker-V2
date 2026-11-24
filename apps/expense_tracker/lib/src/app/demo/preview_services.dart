import 'dart:math';

import 'package:core/money/amount_format.dart' show roundHalfAwayFromZero;

import '../../core/platform/sync_job.dart';
import '../../core/ledger/ledger.dart';
import '../../core/platform/preferences.dart';
import '../../core/platform/screen_privacy.dart';
import '../../features/backup/model/backup_manager.dart';
import '../../features/reminders/model/reminder_alerts.dart';
import '../../core/time/app_clock.dart';

import 'package:core/time/utc_days.dart';

/// The web preview's stand-ins for the phone: notifications that go
/// nowhere, screen hiding kept in memory, made-up daily closes and keys
/// that keep nothing, so 通知與提醒, 安全, 備份與還原, their panels and
/// each holding's chart can be looked at; nothing leaves the browser.
({
  Notifier notifier,
  ScreenPrivacy privacy,
  DemoPrices market,
  BackupManager backupManager,
})
previewServices(Preferences preferences, {Ledger Function()? ledger}) => (
  notifier: Notifier(const _NoNotifications(), preferences),
  privacy: ScreenPrivacy.inMemory(),
  market: DemoPrices(ledger),
  backupManager: DemoBackupManager(),
);

/// Keys and backups that keep nothing: every export is cancelled, the
/// password is only remembered while the page is open.
final class DemoBackupManager implements BackupManager {
  var _password = false;

  @override
  Future<bool> exportBackup() async => false;

  @override
  Future<bool> exportFile(String name, String text) async => false;

  @override
  Future<bool> exportBytes(String name, List<int> bytes) async => false;

  @override
  DateTime? get cloudCopyAt => null;

  @override
  DateTime? get googleTakenAt => null;

  @override
  Future<String?> readFile() async => null;

  @override
  bool get hasPassword => _password;

  @override
  Future<void> setPassword(String next) async => _password = true;

  @override
  Future<void> changePassword(String current, String next) async {}

  @override
  Future<String> newRecoveryCode() async => 'ABCD-EFGH-JKLM-NPQR';

  /// The preview has no phone to confirm a fingerprint.
  @override
  bool get canUseFingerprint => false;

  @override
  bool get fingerprintOn => false;

  @override
  Future<bool> turnFingerprint({required bool on}) async => false;

  @override
  bool get recoveryGiven => true;

  @override
  Future<void> lock() async {}

  @override
  Future<String> restoreAnother() async => '';

  @override
  DateTime? get exportedAt => null;

  @override
  bool get passwordBelowRule => false;

  /// The preview keeps no keys, so holds no password to any rule.
  @override
  String get passwordRule => '';

  @override
  String? refusePassword(String password) => null;

  @override
  String get passphraseRule => '';

  @override
  String? refusePassphrase(String passphrase) => null;

  var _passphrase = false;

  @override
  bool get hasBackupPassphrase => _passphrase;

  @override
  Future<void> setBackupPassphrase(String passphrase) async =>
      _passphrase = true;

  @override
  Future<void> removeBackupPassphrase() async => _passphrase = false;

  @override
  Future<void> resetKeys(String? currentPassword) async {}
}

/// Made-up daily closes for the demo's holdings: a walk of its own for
/// each code, the same each time, ending on the price the ledger holds.
final class DemoPrices extends SyncJob implements PriceHistory {
  DemoPrices(this._ledger) : super('收盤價');

  final Ledger Function()? _ledger;

  @override
  Future<void> refresh({bool force = false}) async {}

  @override
  Future<List<(DateTime, double)>> history(String code, DateTime from) async {
    final ledger = _ledger?.call();
    final today = ledger?.today ?? AppClock.today();
    final end = ledger?.holding(code)?.price ?? 100;
    final days = <DateTime>[
      for (
        var d = dayOf(from);
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
        (day, roundHalfAwayFromZero(walk[i] * scale, 2) / 100),
    ];
  }
}

final class _NoNotifications implements NotifyPort {
  const _NoNotifications();

  @override
  Future<bool> access() async => true;

  @override
  Future<void> schedule(ReminderPlan plan) async {}

  @override
  Future<void> test({required bool exact}) async {}

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
