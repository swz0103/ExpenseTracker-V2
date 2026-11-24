import 'dart:io';

import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import '../core/diagnostics/error_log.dart';
import '../core/diagnostics/error_steps.dart';
import '../core/ledger/persistence/sql_ledger_data_source.dart';
import '../core/platform/memory_keystore.dart';
import '../core/platform/startup.dart';
import '../core/platform/unlock_attempts.dart';
import '../core/time/app_clock.dart';
import 'platform.dart';

/// The only production composition (code audit C-01): the encrypted ledger
/// in [directory], opened through [Startup]. The memory preview is not
/// reachable from here; a test walks the imports to keep it that way.
/// Every password set is held to the vault's one policy
/// (`PasswordPolicy.standard`); a ledger opened without a password keeps
/// its key sealed by the Android Keystore, never in plain form.
/// Wrong passwords are slowed down by the vault's one table
/// (`AttemptPolicy.standard`), the wait measured by [uptime] if it can be.
Startup productionStartup(
  Directory directory, {
  DeviceUnlock? device,
  UptimeSource? uptime,
}) => Startup(
  LedgerVault(
    directory,
    codec: KeyringCodec(),
    now: AppClock.now,
    noteFailed: (error, stack) =>
        ErrorLog.instance.record(ErrorSteps.recordsKeptNote, error, stack),
  ),
  device: device,
  check: SqlLedgerDataSource.check,
  checkRestored: SqlLedgerDataSource.checkRestored,
  quickKey: Platform.isAndroid
      ? const KeystoreQuickKey()
      : MemoryKeystore.instance,
  uptime: uptime,
);

/// Where this device keeps the ledger: the app's private folder on
/// Android, a folder in the home directory on desktop development builds.
Future<Directory> applicationDirectory() async {
  if (Platform.isAndroid) return androidFilesDirectory();
  final home = Platform.isWindows
      ? Platform.environment['APPDATA']
      : Platform.environment['HOME'];
  if (Platform.isIOS || home == null) {
    throw UnsupportedError('No ledger directory on this platform yet.');
  }
  return Directory('$home/.expense_tracker_v2');
}
